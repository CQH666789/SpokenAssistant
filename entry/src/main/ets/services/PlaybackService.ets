import { media } from '@kit.MediaKit';

export class PlaybackService {
  private player?: media.AVPlayer;

  async play(url: string): Promise<void> {
    if (!url) {
      return;
    }

    await this.release();
    this.player = await media.createAVPlayer();
    this.player.url = url;
    await this.player.prepare();
    await this.player.play();
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
}
