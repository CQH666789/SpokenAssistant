import { media } from '@kit.MediaKit';

export class PlaybackService {
  private player?: media.AVPlayer;
  private onComplete?: () => void;

  setOnComplete(callback: () => void): void {
    this.onComplete = callback;
  }

  async play(url: string): Promise<void> {
    if (!url) {
      return;
    }

    await this.release();
    const player = await media.createAVPlayer();
    this.player = player;
    player.on('stateChange', (state: media.AVPlayerState) => {
      if (state === 'completed') {
        this.onComplete?.();
      }
    });
    player.url = url;
    await this.waitForState(player, 'initialized', 8000);
    await player.prepare();
    await this.waitForState(player, 'prepared', 8000);
    await player.play();
  }

  async pause(): Promise<void> {
    if (!this.player) {
      return;
    }
    await this.player.pause();
  }

  async release(): Promise<void> {
    if (!this.player) {
      return;
    }
    try {
      await this.player.release();
    } catch (_) {
      // Playback cleanup is best-effort.
    }
    this.player = undefined;
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
}
