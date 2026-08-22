[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Url,

    [string]$OutputDirectory = (Join-Path (Get-Location) 'downloads'),

    [ValidateRange(144, 4320)]
    [int]$MaxHeight = 1440,

    [bool]$IncludeAudio = $true,

    [bool]$IncludeCover = $true,

    [ValidateSet('Folder', 'Flat')]
    [string]$StorageMode = 'Folder',

    [switch]$UpdateYtDlp
)

$ErrorActionPreference = 'Stop'

try {
    $parsedUrl = [Uri]$Url
} catch {
    throw "Invalid URL: $Url"
}

if (-not $parsedUrl.IsAbsoluteUri -or $parsedUrl.Scheme -notin @('http', 'https')) {
    throw 'Only absolute HTTP and HTTPS URLs are supported.'
}

function Find-Executable {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$WingetPackagePrefixes
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $wingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (-not (Test-Path -LiteralPath $wingetRoot)) {
        return $null
    }

    foreach ($prefix in $WingetPackagePrefixes) {
        $packageDirectories = Get-ChildItem -LiteralPath $wingetRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }
        foreach ($directory in $packageDirectories) {
            $candidate = Get-ChildItem -LiteralPath $directory.FullName -Filter "$Name.exe" -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($candidate) {
                return $candidate.FullName
            }
        }
    }

    return $null
}

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCommand) {
    throw 'Python was not found on PATH.'
}
$python = $pythonCommand.Source

if ($UpdateYtDlp) {
    & $python -m pip install --upgrade yt-dlp
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to update yt-dlp.'
    }
}

& $python -m yt_dlp --version | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw 'yt-dlp is not installed. Run: python -m pip install --upgrade yt-dlp'
}

$ffmpeg = Find-Executable -Name 'ffmpeg' -WingetPackagePrefixes @('yt-dlp.FFmpeg_', 'Gyan.FFmpeg_')
$ffprobe = Find-Executable -Name 'ffprobe' -WingetPackagePrefixes @('yt-dlp.FFmpeg_', 'Gyan.FFmpeg_')
$deno = Find-Executable -Name 'deno' -WingetPackagePrefixes @('DenoLand.Deno_')

if (-not $ffmpeg -or -not $ffprobe) {
    throw 'FFmpeg and FFprobe are required.'
}
if (-not $deno) {
    throw 'Deno is required for reliable YouTube extraction.'
}

$ffmpegDirectory = Split-Path $ffmpeg
$denoDirectory = Split-Path $deno
$env:PATH = "$ffmpegDirectory;$denoDirectory;$env:PATH"

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$resolvedOutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$resultFile = Join-Path $resolvedOutputDirectory ".download-result-$([Guid]::NewGuid().ToString('N')).txt"

$formatSelector = if ($IncludeAudio) {
    "bv[height<=$MaxHeight][ext=mp4]+ba[ext=m4a]/b[height<=$MaxHeight][ext=mp4]/bv[height<=$MaxHeight]+ba/b[height<=$MaxHeight]"
} else {
    "bv[height<=$MaxHeight][ext=mp4]/bv[height<=$MaxHeight]"
}
$outputTemplate = if ($StorageMode -eq 'Folder') {
    '%(title)s [%(id)s]/video.%(ext)s'
} else {
    '%(title)s [%(id)s].%(ext)s'
}
$downloadArguments = @(
    '-m', 'yt_dlp',
    '--no-playlist',
    '--no-continue',
    '--http-chunk-size', '5M',
    '--retries', '10',
    '--fragment-retries', '10',
    '--js-runtimes', 'deno',
    '--ffmpeg-location', $ffmpegDirectory,
    '-f', $formatSelector,
    '--merge-output-format', 'mp4',
    '--remux-video', 'mp4',
    '--windows-filenames',
    '-P', $resolvedOutputDirectory,
    '-o', $outputTemplate,
    '--print-to-file', 'after_move:%(filepath)s', $resultFile,
    $Url
)
if ($IncludeCover) {
    $urlArgument = $downloadArguments[-1]
    $downloadArguments = $downloadArguments[0..($downloadArguments.Count - 2)] + @(
        '--write-thumbnail',
        '--convert-thumbnails', 'jpg',
        $urlArgument
    )
}

& $python @downloadArguments
if ($LASTEXITCODE -ne 0) {
    throw "yt-dlp failed with exit code $LASTEXITCODE."
}

if (-not (Test-Path -LiteralPath $resultFile -PathType Leaf)) {
    throw 'yt-dlp completed without reporting a final file.'
}

$finalFile = (Get-Content -LiteralPath $resultFile -Encoding utf8 | Select-Object -Last 1).Trim()
Remove-Item -LiteralPath $resultFile -Force
if (-not (Test-Path -LiteralPath $finalFile -PathType Leaf)) {
    throw "Final file does not exist: $finalFile"
}

$mediaFolder = Split-Path $finalFile
$downloadedThumbnail = [IO.Path]::ChangeExtension($finalFile, 'jpg')
$coverFile = if ($StorageMode -eq 'Folder') {
    Join-Path $mediaFolder 'cover.jpg'
} else {
    $downloadedThumbnail
}
if ($IncludeCover) {
    if ($StorageMode -eq 'Folder' -and (Test-Path -LiteralPath $downloadedThumbnail -PathType Leaf)) {
        Move-Item -LiteralPath $downloadedThumbnail -Destination $coverFile -Force
    }
    if (-not (Test-Path -LiteralPath $coverFile -PathType Leaf)) {
        throw "Cover image does not exist: $coverFile"
    }
}

$probeJson = & $ffprobe -v error -show_entries 'format=duration,size,format_name:stream=index,codec_type,codec_name,width,height,channels,sample_rate' -of json $finalFile
if ($LASTEXITCODE -ne 0) {
    throw 'FFprobe could not inspect the final file.'
}

$probe = $probeJson | ConvertFrom-Json
$videoStreams = @($probe.streams | Where-Object { $_.codec_type -eq 'video' })
$audioStreams = @($probe.streams | Where-Object { $_.codec_type -eq 'audio' })

if ($videoStreams.Count -lt 1) {
    throw 'The final MP4 has no video stream.'
}
if ($IncludeAudio -and $audioStreams.Count -lt 1) {
    throw 'The final MP4 has no audio stream.'
}
if (-not $IncludeAudio -and $audioStreams.Count -gt 0) {
    throw 'The final MP4 unexpectedly contains an audio stream.'
}
if ("$($probe.format.format_name)" -notmatch 'mp4') {
    throw 'The final file is not an MP4 container.'
}

$video = $videoStreams[0]
$audio = if ($IncludeAudio) { $audioStreams[0] } else { $null }

if ($video.codec_name -ne 'h264' -or ($IncludeAudio -and $audio.codec_name -ne 'aac')) {
    $transcodeFile = Join-Path $mediaFolder ".video-h264-$([Guid]::NewGuid().ToString('N')).mp4"
    $backupFile = Join-Path $mediaFolder ".video-source-$([Guid]::NewGuid().ToString('N')).mp4"
    $audioArguments = if (-not $IncludeAudio) {
        @('-an')
    } elseif ($audio.codec_name -eq 'aac') {
        @('-c:a', 'copy')
    } else {
        @('-c:a', 'aac', '-b:a', '192k')
    }

    if ($video.codec_name -eq 'h264') {
        $videoArguments = @('-c:v', 'copy')
        $encodersToTry = @('copy')
    } else {
        $encodersToTry = @('qsv', 'libx264')
    }

    $transcodeSucceeded = $false
    foreach ($encoder in $encodersToTry) {
        if (Test-Path -LiteralPath $transcodeFile) {
            [IO.File]::Delete($transcodeFile)
        }

        if ($encoder -eq 'qsv') {
            $videoArguments = @('-c:v', 'h264_qsv', '-preset', 'slow', '-global_quality', '20', '-profile:v', 'high', '-pix_fmt', 'nv12')
        } elseif ($encoder -eq 'libx264') {
            $videoArguments = @('-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-profile:v', 'high', '-pix_fmt', 'yuv420p')
        }

        $transcodeArguments = @(
            '-hide_banner', '-y',
            '-i', $finalFile,
            '-map', '0:v:0'
        )
        if ($IncludeAudio) {
            $transcodeArguments += @('-map', '0:a:0')
        }
        $transcodeArguments += $videoArguments + $audioArguments + @('-movflags', '+faststart', $transcodeFile)

        & $ffmpeg @transcodeArguments
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $transcodeFile -PathType Leaf)) {
            $transcodeSucceeded = $true
            break
        }
    }

    if (-not $transcodeSucceeded) {
        throw 'Unable to create an H.264 MP4 with audio.'
    }

    $convertedJson = & $ffprobe -v error -show_entries 'format=duration,size,format_name:stream=index,codec_type,codec_name,width,height,channels,sample_rate' -of json $transcodeFile
    if ($LASTEXITCODE -ne 0) {
        throw 'FFprobe could not inspect the H.264 conversion.'
    }
    $convertedProbe = $convertedJson | ConvertFrom-Json
    $convertedVideo = @($convertedProbe.streams | Where-Object { $_.codec_type -eq 'video' })[0]
    $convertedAudio = @($convertedProbe.streams | Where-Object { $_.codec_type -eq 'audio' })[0]
    if (-not $convertedVideo -or $convertedVideo.codec_name -ne 'h264' -or ($IncludeAudio -and -not $convertedAudio) -or (-not $IncludeAudio -and $convertedAudio) -or "$($convertedProbe.format.format_name)" -notmatch 'mp4') {
        throw 'The converted file failed H.264 MP4 stream verification.'
    }

    $scanArguments = @('-v', 'error', '-xerror', '-i', $transcodeFile, '-map', '0:v:0')
    if ($IncludeAudio) {
        $scanArguments += @('-map', '0:a:0')
    }
    $scanArguments += @('-c', 'copy', '-f', 'null', 'NUL')
    & $ffmpeg @scanArguments
    if ($LASTEXITCODE -ne 0) {
        throw 'The converted H.264 MP4 failed its packet integrity scan.'
    }

    Move-Item -LiteralPath $finalFile -Destination $backupFile
    try {
        Move-Item -LiteralPath $transcodeFile -Destination $finalFile
        $finalJson = & $ffprobe -v error -show_entries 'format=duration,size,format_name:stream=index,codec_type,codec_name,width,height,channels,sample_rate' -of json $finalFile
        if ($LASTEXITCODE -ne 0) {
            throw 'FFprobe could not inspect the replaced final file.'
        }
        $probe = $finalJson | ConvertFrom-Json
        $videoStreams = @($probe.streams | Where-Object { $_.codec_type -eq 'video' })
        $audioStreams = @($probe.streams | Where-Object { $_.codec_type -eq 'audio' })
        $video = $videoStreams[0]
        $audio = if ($IncludeAudio) { $audioStreams[0] } else { $null }
        if (-not $video -or $video.codec_name -ne 'h264' -or ($IncludeAudio -and -not $audio) -or (-not $IncludeAudio -and $audioStreams.Count -gt 0) -or "$($probe.format.format_name)" -notmatch 'mp4') {
            throw 'The replaced final file failed verification.'
        }
        [IO.File]::Delete($backupFile)
    } catch {
        if (Test-Path -LiteralPath $finalFile) {
            [IO.File]::Delete($finalFile)
        }
        Move-Item -LiteralPath $backupFile -Destination $finalFile
        throw
    }
}

$result = [pscustomobject]@{
    Folder     = (Resolve-Path -LiteralPath $mediaFolder).Path
    File       = (Resolve-Path -LiteralPath $finalFile).Path
    Cover      = if ($IncludeCover) { (Resolve-Path -LiteralPath $coverFile).Path } else { $null }
    StorageMode = $StorageMode
    Width      = $video.width
    Height     = $video.height
    VideoCodec = $video.codec_name
    AudioCodec = if ($audio) { $audio.codec_name } else { $null }
    Channels   = if ($audio) { $audio.channels } else { $null }
    Duration   = [math]::Round([double]$probe.format.duration, 3)
    SizeBytes  = [int64]$probe.format.size
}

$result | Format-List

