import { media } from '@kit.MediaKit';
import fs from '@ohos.file.fs';
import type { Context } from '@kit.AbilityKit';
import type { RecordingResult } from '../models/TrainingModels';

export class RecorderService {
  private recorder?: media.AVRecorder;
  private fileFd: number = -1;
  private recordingPath: string = '';
  private startedAt: number = 0;
  private readonly context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  async start(): Promise<void> {
    await this.release();

    const dir = `${this.context.cacheDir}/recordings`;
    try {
      fs.mkdirSync(dir, true);
    } catch (_) {
      // The directory may already exist.
    }

    this.recordingPath = `${dir}/spoken-${Date.now()}.m4a`;
    const file = fs.openSync(
      this.recordingPath,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
    );
    this.fileFd = file.fd;

    const profile: media.AVRecorderProfile = {
      audioBitrate: 64000,
      audioChannels: 1,
      audioCodec: media.CodecMimeType.AUDIO_AAC,
      audioSampleRate: 44100,
      fileFormat: media.ContainerFormatType.CFT_MPEG_4A
    };

    const config: media.AVRecorderConfig = {
      audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
      profile,
      url: `fd://${this.fileFd}`,
      maxDuration: 30
    };

    this.recorder = await media.createAVRecorder();
    await this.recorder.prepare(config);
    await this.recorder.start();
    this.startedAt = Date.now();
  }

  async stop(): Promise<RecordingResult> {
    const durationMs = Math.max(Date.now() - this.startedAt, 0);
    if (this.recorder) {
      await this.recorder.stop();
    }
    await this.releaseRecorderOnly();

    if (this.fileFd >= 0) {
      fs.closeSync(this.fileFd);
      this.fileFd = -1;
    }

    return {
      path: this.recordingPath,
      durationMs
    };
  }

  async release(): Promise<void> {
    await this.releaseRecorderOnly();
    if (this.fileFd >= 0) {
      fs.closeSync(this.fileFd);
      this.fileFd = -1;
    }
  }

  private async releaseRecorderOnly(): Promise<void> {
    if (!this.recorder) {
      return;
    }
    try {
      await this.recorder.release();
    } catch (_) {
      // Release best effort; the UI owns user-visible failure states.
    }
    this.recorder = undefined;
  }
}
