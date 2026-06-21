import type { Context } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { http } from '@kit.NetworkKit';
import fs from '@ohos.file.fs';

const SIMULATOR_PROXY: http.HttpProxy = {
  host: '10.0.2.2',
  port: 7897,
  exclusionList: []
};

export class PlaybackService {
  private player?: media.AVPlayer;
  private onComplete?: () => void;
  private playbackFd: number = -1;
  private completionTimer: number = -1;
  private readonly context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  setOnComplete(callback: () => void): void {
    this.onComplete = callback;
  }

  async play(url: string): Promise<void> {
    if (!url) {
      return;
    }

    await this.release();
    const localPath = await this.downloadAudio(url);
    const stat = fs.statSync(localPath);
    const file = fs.openSync(localPath, fs.OpenMode.READ_ONLY);
    this.playbackFd = file.fd;

    const player = await media.createAVPlayer();
    this.player = player;
    player.on('stateChange', (state: media.AVPlayerState) => {
      if (state === 'completed') {
        this.completePlayback();
      }
    });
    player.fdSrc = {
      fd: this.playbackFd,
      offset: 0,
      length: stat.size
    };
    await this.waitForState(player, 'initialized', 8000);
    await player.prepare();
    await this.waitForState(player, 'prepared', 8000);
    await player.play();
    this.scheduleCompletion(player.duration);
  }

  async pause(): Promise<void> {
    await this.release();
  }

  async release(): Promise<void> {
    if (!this.player) {
      this.clearCompletionTimer();
      this.closePlaybackFd();
      return;
    }
    try {
      await this.player.release();
    } catch (_) {
      // Playback cleanup is best-effort.
    }
    this.player = undefined;
    this.clearCompletionTimer();
    this.closePlaybackFd();
  }

  private async downloadAudio(url: string): Promise<string> {
    try {
      return await this.downloadAudioWithMode(url, false);
    } catch (_) {
      return await this.downloadAudioWithMode(url, true);
    }
  }

  private async downloadAudioWithMode(url: string, useSimulatorProxy: boolean): Promise<string> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: useSimulatorProxy ? 30000 : 5000,
        readTimeout: 30000
      };
      if (useSimulatorProxy) {
        options.usingProxy = SIMULATOR_PROXY;
      }

      const response = await request.request(url, options);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`Reference audio download failed: ${response.responseCode}`);
      }

      const audioData = response.result as ArrayBuffer;
      const dir = `${this.context.cacheDir}/reference-audio`;
      try {
        fs.mkdirSync(dir, true);
      } catch (_) {
        // Directory may already exist.
      }

      const path = `${dir}/reference-${Date.now()}.wav`;
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, audioData);
      } finally {
        fs.closeSync(file.fd);
      }
      return path;
    } finally {
      request.destroy();
    }
  }

  private waitForState(player: media.AVPlayer, expectedState: media.AVPlayerState, timeoutMs: number): Promise<void> {
    if (player.state === expectedState) {
      return Promise.resolve();
    }

    return new Promise<void>((resolve, reject) => {
      let settled = false;
      const timer = setTimeout(() => {
        finish(() => reject(new Error(`Playback timed out waiting for ${expectedState}, current state: ${player.state}`)));
      }, timeoutMs);

      const handler = (state: media.AVPlayerState) => {
        if (state === expectedState) {
          finish(resolve);
          return;
        }
        if (state === 'error' || state === 'released') {
          finish(() => reject(new Error(`Playback entered invalid state: ${state}`)));
        }
      };

      const finish = (callback: () => void) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        player.off('stateChange', handler);
        callback();
      };

      player.on('stateChange', handler);
    });
  }

  private scheduleCompletion(durationMs: number): void {
    this.clearCompletionTimer();
    if (durationMs <= 0) {
      return;
    }
    this.completionTimer = setTimeout(() => {
      this.completePlayback();
    }, durationMs + 500);
  }

  private completePlayback(): void {
    this.onComplete?.();
    void this.release();
  }

  private clearCompletionTimer(): void {
    if (this.completionTimer >= 0) {
      clearTimeout(this.completionTimer);
      this.completionTimer = -1;
    }
  }

  private closePlaybackFd(): void {
    if (this.playbackFd >= 0) {
      fs.closeSync(this.playbackFd);
      this.playbackFd = -1;
    }
  }
}
