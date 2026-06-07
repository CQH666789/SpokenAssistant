import type { Context } from '@kit.AbilityKit';
import type { EvaluationResult, PronunciationCorrection, RecordingResult, TrainingSentence, TrainingStage } from '../models/TrainingModels';
import { TRAINING_SENTENCES } from '../models/TrainingModels';
import { PermissionService } from '../services/PermissionService';
import { PlaybackService } from '../services/PlaybackService';
import { RecorderService } from '../services/RecorderService';
import { TrainingApi } from '../services/TrainingApi';

const COLOR_BG = '#F6F2EA';
const COLOR_INK = '#201F1B';
const COLOR_MUTED = '#706A5E';
const COLOR_LINE = '#DDD4C5';
const COLOR_CARD = '#FFFDF8';
const COLOR_PRIMARY = '#D66A35';
const COLOR_PRIMARY_DARK = '#9B4323';
const COLOR_GOOD = '#2C8572';
const COLOR_BLUE = '#3B6D8F';
const COLOR_WARN_BG = '#FCE8DA';

@Entry
@Component
struct Index {
  @State private sentenceIndex: number = 0;
  @State private sentence: TrainingSentence = TRAINING_SENTENCES[0];
  @State private stage: TrainingStage = 'idle';
  @State private elapsedSeconds: number = 0;
  @State private result?: EvaluationResult = undefined;
  @State private errorMessage: string = '';
  @State private isPlaying: boolean = false;
  @State private completedCount: number = 0;
  @State private scoreTotal: number = 0;
  @State private bestScore: number = 0;
  @State private averageScore: number = 0;

  private recorder?: RecorderService;
  private playback: PlaybackService = new PlaybackService();
  private timerId: number = -1;

  aboutToAppear(): void {
    const context = getContext(this) as Context;
    this.recorder = new RecorderService(context);
  }

  aboutToDisappear(): void {
    this.stopTimer();
    this.recorder?.release();
    this.playback.release();
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column({ space: 18 }) {
          this.Header()
          this.ProgressStrip()
          this.SentenceCard()
          this.RecorderPanel()
          this.ResultPanel()
        }
        .padding({ left: 20, right: 20, top: 22, bottom: 118 })
        .width('100%')
      }
      .backgroundColor(COLOR_BG)
      .width('100%')
      .height('100%')

      this.BottomBar()
    }
    .backgroundColor(COLOR_BG)
    .width('100%')
    .height('100%')
  }

  @Builder
  private Header() {
    Row() {
      Column({ space: 4 }) {
        Text('SpokenAssistant')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_INK)
        Text('English speaking practice')
          .fontSize(13)
          .fontColor(COLOR_MUTED)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column({ space: 2 }) {
        Text(`${this.sentenceIndex + 1}/${TRAINING_SENTENCES.length}`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_BLUE)
        Text(this.sentence.level)
          .fontSize(11)
          .fontColor(COLOR_MUTED)
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
  }

  @Builder
  private ProgressStrip() {
    Row({ space: 10 }) {
      this.StatTile('Done', `${this.completedCount}`)
      this.StatTile('Best', this.bestScore > 0 ? `${this.bestScore}` : '-')
      this.StatTile('Avg', this.averageScore > 0 ? `${this.averageScore}` : '-')
    }
    .width('100%')
  }

  @Builder
  private StatTile(label: string, value: string) {
    Column({ space: 3 }) {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_INK)
      Text(label)
        .fontSize(11)
        .fontColor(COLOR_MUTED)
    }
    .justifyContent(FlexAlign.Center)
    .height(72)
    .layoutWeight(1)
    .backgroundColor(COLOR_CARD)
    .borderRadius(8)
    .border({ width: 1, color: COLOR_LINE })
  }

  @Builder
  private SentenceCard() {
    Column({ space: 14 }) {
      Row() {
        Text(this.sentence.focus.toUpperCase())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY_DARK)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(COLOR_WARN_BG)
          .borderRadius(14)
        Blank()
        Text(this.sentence.level)
          .fontSize(12)
          .fontColor(COLOR_MUTED)
      }
      .width('100%')

      Text(this.sentence.text)
        .fontSize(25)
        .lineHeight(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_INK)
        .width('100%')

      Text('Read the sentence naturally. Focus on clarity, rhythm, and the highlighted speaking goal.')
        .fontSize(14)
        .lineHeight(20)
        .fontColor(COLOR_MUTED)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(22)
    .backgroundColor(COLOR_CARD)
    .borderRadius(8)
    .border({ width: 1, color: COLOR_LINE })
    .width('100%')
  }

  @Builder
  private RecorderPanel() {
    Column({ space: 16 }) {
      Row() {
        Text(this.statusTitle())
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_INK)
        Blank()
        Text(this.formattedTime())
          .fontSize(14)
          .fontColor(this.stage === 'recording' ? COLOR_PRIMARY_DARK : COLOR_MUTED)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')

      Row({ space: 7 }) {
        ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], (item: number) => {
          Column()
            .width(8)
            .height(this.waveHeight(item))
            .backgroundColor(this.stage === 'recording' ? COLOR_PRIMARY : COLOR_LINE)
            .borderRadius(5)
        })
      }
      .height(54)
      .justifyContent(FlexAlign.Center)
      .width('100%')

      Button(this.primaryButtonText())
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .height(64)
        .width(164)
        .borderRadius(32)
        .backgroundColor(this.stage === 'recording' ? COLOR_PRIMARY_DARK : COLOR_PRIMARY)
        .enabled(!this.isBusy())
        .onClick(() => {
          void this.handlePrimaryAction();
        })

      if (this.errorMessage.length > 0 || this.stage === 'permissionDenied') {
        Text(this.errorMessage || 'Microphone permission is required to record your voice.')
          .fontSize(13)
          .lineHeight(18)
          .fontColor(COLOR_PRIMARY_DARK)
          .textAlign(TextAlign.Center)
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Center)
    .padding(20)
    .backgroundColor(COLOR_CARD)
    .borderRadius(8)
    .border({ width: 1, color: COLOR_LINE })
    .width('100%')
  }

  @Builder
  private ResultPanel() {
    if (this.result) {
      Column({ space: 16 }) {
        Row({ space: 16 }) {
          Stack() {
            Progress({
              value: this.result.overallScore,
              total: 100,
              type: ProgressType.Ring
            })
              .width(94)
              .height(94)
              .color(COLOR_GOOD)
              .backgroundColor('#E7DFD1')

            Column({ space: 1 }) {
              Text(`${this.result.overallScore}`)
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_INK)
              Text('score')
                .fontSize(11)
                .fontColor(COLOR_MUTED)
            }
          }

          Column({ space: 9 }) {
            this.ScoreRow('Fluency', this.result.fluencyScore, COLOR_BLUE)
            this.ScoreRow('Pronunciation', this.result.pronunciationScore, COLOR_GOOD)
            this.ScoreRow('Intonation', this.result.intonationScore, COLOR_PRIMARY)
          }
          .layoutWeight(1)
        }
        .width('100%')

        Text(this.result.feedback)
          .fontSize(15)
          .lineHeight(22)
          .fontColor(COLOR_INK)
          .width('100%')

        Column({ space: 10 }) {
          ForEach(this.result.corrections, (item: PronunciationCorrection) => {
            this.CorrectionRow(item)
          }, (item: PronunciationCorrection) => `${item.word}-${item.issue}`)
        }
        .width('100%')

        Button(this.playbackButtonText())
          .height(48)
          .width('100%')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_INK)
          .backgroundColor(this.hasReferenceAudio() ? '#EAE2D3' : '#F3EDE2')
          .borderRadius(6)
          .enabled(this.hasReferenceAudio())
          .onClick(() => {
            void this.togglePlayback();
          })
      }
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .backgroundColor(COLOR_CARD)
      .borderRadius(8)
      .border({ width: 1, color: COLOR_LINE })
      .width('100%')
    } else {
      Column({ space: 10 }) {
        Text('Feedback will appear here')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_INK)
        Text('After you finish recording, SpokenAssistant checks clarity, fluency, and intonation.')
          .fontSize(14)
          .lineHeight(20)
          .fontColor(COLOR_MUTED)
          .textAlign(TextAlign.Center)
      }
      .padding(20)
      .backgroundColor('#EFE8DC')
      .borderRadius(8)
      .width('100%')
    }
  }

  @Builder
  private ScoreRow(label: string, value: number, color: string) {
    Column({ space: 5 }) {
      Row() {
        Text(label)
          .fontSize(12)
          .fontColor(COLOR_MUTED)
        Blank()
        Text(`${value}`)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_INK)
      }
      .width('100%')

      Progress({ value, total: 100, type: ProgressType.Linear })
        .height(6)
        .color(color)
        .backgroundColor('#E7DFD1')
        .width('100%')
    }
    .width('100%')
  }

  @Builder
  private CorrectionRow(item: PronunciationCorrection) {
    Column({ space: 5 }) {
      Row() {
        Text(item.word)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_INK)
        Blank()
        Text('Fix')
          .fontSize(11)
          .fontColor(COLOR_PRIMARY_DARK)
      }
      .width('100%')

      Text(item.issue)
        .fontSize(13)
        .fontColor(COLOR_MUTED)
        .lineHeight(18)
        .width('100%')

      Text(item.suggestion)
        .fontSize(13)
        .fontColor(COLOR_INK)
        .lineHeight(18)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor('#F6F0E5')
    .borderRadius(6)
    .width('100%')
  }

  @Builder
  private BottomBar() {
    Row({ space: 12 }) {
      Button('Retry')
        .height(48)
        .layoutWeight(1)
        .fontSize(15)
        .fontColor(COLOR_INK)
        .backgroundColor('#EAE2D3')
        .borderRadius(6)
        .enabled(!this.isBusy())
        .onClick(() => {
          this.resetAttempt();
        })

      Button('Next sentence')
        .height(48)
        .layoutWeight(1)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor(COLOR_GOOD)
        .borderRadius(6)
        .enabled(!this.isBusy())
        .onClick(() => {
          this.nextSentence();
        })
    }
    .padding({ left: 20, right: 20, top: 14, bottom: 18 })
    .backgroundColor('#FFFDF8')
    .border({ width: { top: 1 }, color: COLOR_LINE })
    .width('100%')
  }

  private async handlePrimaryAction(): Promise<void> {
    if (this.stage === 'recording') {
      await this.stopRecordingAndEvaluate();
      return;
    }
    await this.startRecording();
  }

  private async startRecording(): Promise<void> {
    this.errorMessage = '';
    const context = getContext(this) as Context;
    const allowed = await PermissionService.requestMicrophone(context);
    if (!allowed) {
      this.stage = 'permissionDenied';
      this.errorMessage = 'Please allow microphone access to practice speaking.';
      return;
    }

    try {
      if (!this.recorder) {
        this.recorder = new RecorderService(context);
      }
      await this.recorder.start();
      this.elapsedSeconds = 0;
      this.result = undefined;
      this.stage = 'recording';
      this.startTimer();
    } catch (err) {
      this.stage = 'error';
      this.errorMessage = `Recording could not start: ${JSON.stringify(err)}`;
    }
  }

  private async stopRecordingAndEvaluate(): Promise<void> {
    try {
      this.stopTimer();
      this.stage = 'uploading';
      const recording: RecordingResult = await this.recorder!.stop();
      this.stage = 'evaluating';
      this.result = await TrainingApi.evaluate(this.sentence, recording);
      this.recordScore(this.result.overallScore);
      this.stage = 'complete';
    } catch (err) {
      this.stage = 'error';
      this.errorMessage = `Evaluation failed: ${JSON.stringify(err)}`;
    }
  }

  private async togglePlayback(): Promise<void> {
    if (!this.result) {
      return;
    }
    if (!this.hasReferenceAudio()) {
      return;
    }
    if (this.isPlaying) {
      await this.playback.pause();
      this.isPlaying = false;
      return;
    }
    try {
      await this.playback.play(this.result.referenceAudioUrl);
      this.isPlaying = true;
    } catch (err) {
      this.errorMessage = `Model voice could not play: ${JSON.stringify(err)}`;
      this.isPlaying = false;
    }
  }

  private nextSentence(): void {
    this.sentenceIndex = (this.sentenceIndex + 1) % TRAINING_SENTENCES.length;
    this.sentence = TRAINING_SENTENCES[this.sentenceIndex];
    this.resetAttempt();
  }

  private resetAttempt(): void {
    this.stopTimer();
    this.stage = 'idle';
    this.elapsedSeconds = 0;
    this.result = undefined;
    this.errorMessage = '';
    this.isPlaying = false;
    this.playback.release();
  }

  private recordScore(score: number): void {
    this.completedCount += 1;
    this.scoreTotal += score;
    this.bestScore = Math.max(this.bestScore, score);
    this.averageScore = Math.round(this.scoreTotal / this.completedCount);
  }

  private startTimer(): void {
    this.stopTimer();
    this.timerId = setInterval(() => {
      this.elapsedSeconds += 1;
    }, 1000);
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private statusTitle(): string {
    switch (this.stage) {
      case 'recording':
        return 'Listening now';
      case 'uploading':
        return 'Uploading your take';
      case 'evaluating':
        return 'Checking pronunciation';
      case 'complete':
        return 'Feedback ready';
      case 'permissionDenied':
        return 'Microphone blocked';
      case 'error':
        return 'Needs another try';
      default:
        return 'Ready to practice';
    }
  }

  private primaryButtonText(): string {
    if (this.stage === 'recording') {
      return 'Stop';
    }
    if (this.stage === 'uploading' || this.stage === 'evaluating') {
      return 'Checking';
    }
    return 'Record';
  }

  private playbackButtonText(): string {
    if (!this.hasReferenceAudio()) {
      return 'Model voice unavailable';
    }
    return this.isPlaying ? 'Pause model voice' : 'Play model voice';
  }

  private hasReferenceAudio(): boolean {
    if (!this.result) {
      return false;
    }
    return this.result.referenceAudioUrl.length > 0;
  }

  private isBusy(): boolean {
    return this.stage === 'uploading' || this.stage === 'evaluating';
  }

  private formattedTime(): string {
    const seconds = this.elapsedSeconds % 60;
    const minutes = Math.floor(this.elapsedSeconds / 60);
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }

  private waveHeight(index: number): number {
    const values = [18, 34, 24, 46, 30, 52, 36, 42, 20, 48, 28, 38];
    if (this.stage !== 'recording') {
      return values[index] * 0.55;
    }
    return values[(index + this.elapsedSeconds) % values.length];
  }
}
