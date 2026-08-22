# download-2k-mp4

A Codex skill that downloads an authorized video URL, selects the best video up to a requested resolution, optionally includes audio and a cover image, produces an H.264 MP4, and verifies the result.

## Install as a Codex skill

On Windows PowerShell:

```powershell
git clone https://github.com/benligo/download-2k-mp4-skill.git "$env:USERPROFILE\.codex\skills\download-2k-mp4"
```

Restart Codex after installation so the skill is discovered.

## Prompt format for AI use

Give the AI the skill name and these fields:

```text
Use $download-2k-mp4
Link: https://youtu.be/VIDEO_ID
Resolution: 1440p / 2K
Audio: yes
Cover: yes
Storage: separate folder
Output directory: D:\Videos (optional)
```

Supported choices:

- `Resolution`: a maximum height such as `720p`, `1080p`, `1440p`/`2K`, or `2160p`/`4K`. If unavailable, the skill selects the best lower resolution.
- `Audio`: `yes` to merge the best available audio as AAC; `no` for a silent MP4.
- `Cover`: `yes` to save a JPG thumbnail; `no` to omit it.
- `Storage`: `separate folder` creates `Title [video-id]/video.mp4` and optional `cover.jpg`; `all together` saves matching titled files directly in the output directory.
- `Output directory`: optional. If omitted, the AI should use a suitable local downloads directory.

If one or more choices are missing, the AI should ask once using this compact form:

```text
Please provide: resolution, audio (yes/no), cover (yes/no), and storage (separate folder/all together).
```

Defaults, when the user allows defaults: 2K maximum, audio yes, cover yes, separate folder.

中文调用示例：

```text
使用 $download-2k-mp4
链接：https://youtu.be/VIDEO_ID
分辨率：2K
声音：需要
封面图：需要
存储方式：每个视频单独文件夹
保存位置：D:\Videos
```

## Requirements

- Windows PowerShell 7 or Windows PowerShell 5.1
- Python with `yt-dlp`: `python -m pip install --upgrade yt-dlp`
- FFmpeg and FFprobe
- Deno for reliable YouTube extraction

The script searches PATH first, then common WinGet package directories for FFmpeg, FFprobe, and Deno.

## Direct script use

From the skill directory:

```powershell
& ".\scripts\download_video.ps1" `
  -Url "https://youtu.be/VIDEO_ID" `
  -OutputDirectory "D:\Videos" `
  -MaxHeight 1440 `
  -IncludeAudio $true `
  -IncludeCover $true `
  -StorageMode Folder
```

Use `-StorageMode Flat` to place all titled files in one directory.

## Output guarantees

- MP4 container with H.264/AVC video
- AAC audio when audio is requested
- No audio stream when audio is disabled
- JPG cover when a cover is requested
- FFprobe stream validation and FFmpeg packet integrity scan

Only download content you are authorized to save. The skill does not bypass DRM, paywalls, private access, or geographic restrictions, and it does not use browser cookies unless the user explicitly authorizes that separately.

