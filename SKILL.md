---
name: download-2k-mp4
description: Download an authorized video URL locally with a requested maximum resolution, optional audio and cover, folder or flat storage, H.264 MP4 output, and media verification. Use when a user provides a video link and wants a configurable local download; do not use for DRM, paywalls, private content, or server deployment.
---

# Download 2K MP4

Before downloading, identify these request fields from the user's message:

- URL
- Maximum resolution, such as 720p, 1080p, 1440p/2K, or 2160p/4K
- Audio: include or omit
- Cover image: include or omit
- Storage: one titled folder per video or all files together
- Output directory, if specified

If a required choice cannot be inferred, ask for the missing fields in one compact prompt. Defaults are 1440p, audio included, cover included, and one titled folder per video.

Use the bundled `scripts/download_video.ps1` for deterministic downloads. Resolve it relative to this skill directory rather than assuming a user-specific absolute path:

```powershell
& "<SKILL_DIRECTORY>\scripts\download_video.ps1" `
  -Url "VIDEO_URL" `
  -OutputDirectory "OUTPUT_DIRECTORY" `
  -MaxHeight 1440 `
  -IncludeAudio $true `
  -IncludeCover $true `
  -StorageMode Folder
```

In `Folder` mode, create `Title [video-id]` containing `video.mp4` and optional `cover.jpg`. In `Flat` mode, save `Title [video-id].mp4` and the optional matching `.jpg` directly in the output directory. Select the best video no higher than `MaxHeight`; if that exact resolution is unavailable, use the best lower resolution. Include the best available audio only when requested.

The final video stream must be H.264/AVC, not merely an MP4 container. Keep H.264 video without re-encoding; otherwise transcode to H.264 while preserving the selected resolution. When audio is requested, keep AAC without re-encoding or encode other audio to AAC. The script tries Intel Quick Sync first for H.264 conversion and falls back to stable `libx264` CPU encoding when hardware encoding is unavailable.

The script requires Python with `yt-dlp`, FFmpeg, FFprobe, and Deno. On this Windows machine they are installed through Python/Winget. If YouTube returns extraction or 403 errors, retry once with `-UpdateYtDlp`; the script already uses 5 MiB HTTP chunks and fresh downloads to avoid stale media URLs.

Do not use browser cookies by default. Cookies can expose authenticated sessions; request explicit user permission before adding `--cookies-from-browser` or a cookies file.

After completion, report the absolute video path, optional cover path, storage layout, resolution, video codec, audio status/codec, duration, and file size. Do not present a `.part` file, a non-H.264 video, or output that contradicts the requested audio/cover choices. If requested audio is unavailable, or the source is unsupported, private, paid, geo-blocked, or DRM-protected, stop and report that limitation rather than attempting to bypass access controls.

