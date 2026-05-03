<p align="center">
  <img src="assets/readme/petal-icon.png" alt="Petal app icon" width="120" height="120">
  <h1 align="center">Petal for macOS</h1>
</p>

<p align="center">
  Petal is a native macOS app for fast, local-first audio transcription in a clean, minimal interface.
</p>

<p align="center">
  <a aria-label="Download Latest Version" href="https://github.com/Aayush9029/petal/releases/latest">
    <img alt="Download Latest Version" src="https://img.shields.io/badge/Download%20Mac%20Version-black.svg?style=for-the-badge&logo=apple">
  </a>
  
  <a aria-label="Support Development" href="https://github.com/sponsors/Aayush9029">
    <img alt="Support Development" src="https://img.shields.io/badge/Support%20Development-white.svg?style=for-the-badge&logo=githubsponsors&logoColor=ff5ca8">
  </a>
</p>



  <p align="center">
    <img src="https://github.com/user-attachments/assets/3b5190e8-fe02-4225-9b77-f57c2127fe8d" width="100%">
  </p>


<video src="https://github.com/user-attachments/assets/bd173a8c-604d-4e56-8d39-fb6c63481113"/>




## Install

1. Download the latest version from the release page.
2. Open the `.dmg` and move Petal to `Applications`.
3. Launch Petal and grant microphone/accessibility permissions.

## Supported Transcription Models

<table>
  <thead>
    <tr>
      <th>Provider</th>
      <th>Model(s)</th>
      <th>Notes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td valign="middle"><img src="assets/readme/models/apple.png" alt="Apple" width="28" height="28"> Apple</td>
      <td>Apple Speech Transcriber (version varies by macOS)</td>
      <td>Built in on supported Macs. No model download required.</td>
    </tr>
    <tr>
      <td valign="middle"><img src="assets/readme/models/qwen.png" alt="Qwen" width="28" height="28"> Qwen</td>
      <td>Qwen3 ASR</td>
      <td>Default balanced on-device model.</td>
    </tr>
    <tr>
      <td valign="middle"><img src="assets/readme/models/nvidia.png" alt="FluidAudio" width="28" height="28"> FluidAudio</td>
      <td>Parakeet TDT 0.6B (v3)</td>
      <td>Fast local Parakeet transcription via FluidAudio.</td>
    </tr>
    <tr>
      <td valign="middle"><img src="assets/readme/models/openai.png" alt="Whisper" width="28" height="28"> Whisper</td>
      <td>Whisper Large V3, Whisper Tiny</td>
      <td>High-accuracy and lightweight Whisper options via WhisperKit.</td>
    </tr>
    <tr>
      <td valign="middle"><img src="assets/readme/models/cohere.png" alt="Cohere" width="28" height="28"> Cohere</td>
      <td>Cohere Transcribe 2B (q4f16, fp16)</td>
      <td><b>Experimental</b> — #1 on Open ASR Leaderboard. Hybrid CoreML encoder + ONNX decoder. See <a href="https://github.com/Aayush9029/petal/tree/cohere"><code>cohere</code></a> branch.</td>
    </tr>
    <tr>
      <td valign="middle"><img src="assets/readme/models/mistral.png" alt="Voxtral" width="28" height="28"> Voxtral</td>
      <td>Voxtral BF16, Voxtral 8-bit</td>
      <td>Fast local transcription with higher-end on-device quality.</td>
    </tr>
  </tbody>
</table>

## Features

- Multiple transcription engines, all in one native app.
- Local-first workflow designed for Apple Silicon Macs.
- Fast transcription workflow with quick copy/paste output.
- Raycast extension
  
  <a href="https://www.raycast.com/Aayush9029/petal" title="Install petal Raycast Extension">
    <img src="https://www.raycast.com/Aayush9029/petal/install_button@2x.png?v=1.1" height="48" style="height: 48px;" alt="" />
  </a>
  
## Privacy

Petal is designed for local transcription workflows and keeps the experience on-device where possible.


