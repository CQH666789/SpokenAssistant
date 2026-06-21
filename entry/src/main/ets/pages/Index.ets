import type { Context } from '@kit.AbilityKit';
import type { CoachNextAction, EvaluationResult, PronunciationCorrection, RecordingResult, TrainingHistoryItem, TrainingSentence, TrainingStage } from '../models/TrainingModels';
import { TRAINING_SENTENCES } from '../models/TrainingModels';
import { PermissionService } from '../services/PermissionService';
import { PlaybackService } from '../services/PlaybackService';
import { RecorderService } from '../services/RecorderService';
import { TrainingApi } from '../services/TrainingApi';
import { TrainingHistoryService } from '../services/TrainingHistoryService';

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
const LEVEL_ALL = '全部';
const LEVEL_FILTERS: string[] = [LEVEL_ALL, 'A2', 'B1', 'B2'];

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
  @State private isPlaybackLoading: boolean = false;
  @State private isRefreshingSentence: boolean = false;
  @State private totalCompletedCount: number = 0;
  @State private totalScoreTotal: number = 0;
  @State private totalBestScore: number = 0;
  @State private a2CompletedCount: number = 0;
  @State private a2ScoreTotal: number = 0;
  @State private a2BestScore: number = 0;
  @State private b1CompletedCount: number = 0;
  @State private b1ScoreTotal: number = 0;
  @State private b1BestScore: number = 0;
  @State private b2CompletedCount: number = 0;
  @State private b2ScoreTotal: number = 0;
  @State private b2BestScore: number = 0;
  @State private selectedLevel: string = LEVEL_ALL;
  @State private visibleCompletedCount: number = 0;
  @State private visibleBestScore: number = 0;
  @State private visibleAverageScore: number = 0;
  @State private coachAction?: CoachNextAction = undefined;
  @State private isLoadingCoach: boolean = false;
  @State private coachErrorMessage: string = '';

  private recorder?: RecorderService;
  private playback?: PlaybackService;
  private recentHistory: TrainingHistoryItem[] = [];
  private timerId: number = -1;

  aboutToAppear(): void {
    const context = getContext(this) as Context;
    this.recorder = new RecorderService(context);
    this.playback = new PlaybackService(context);
    this.playback.setOnComplete(() => {
      this.isPlaying = false;
      this.isPlaybackLoading = false;
    });
    void this.loadTrainingHistory(context);
  }

  aboutToDisappear(): void {
    this.stopTimer();
    this.recorder?.release();
    this.playback?.release();
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column({ space: 18 }) {
          this.Header()
          this.ProgressStrip()
          this.LevelSelector()
          this.SentenceCard()
          this.RecorderPanel()
          this.ResultPanel()
          this.CoachPanel()
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
        Text('声练英语')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_INK)
        Text('英语口语跟读训练')
          .fontSize(13)
          .fontColor(COLOR_MUTED)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column({ space: 2 }) {
        Text(`${this.currentSentencePosition()}/${this.filteredSentenceCount()}`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_BLUE)
        Text(this.selectedLevel === LEVEL_ALL ? '全部等级' : this.selectedLevel)
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
      this.CompletedStatTile()
      this.BestStatTile()
      this.AverageStatTile()
    }
    .width('100%')
  }

  @Builder
  private CompletedStatTile() {
    Column({ space: 3 }) {
      Text(`${this.visibleCompletedCount}`)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_INK)
      Text('完成')
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
  private BestStatTile() {
    Column({ space: 3 }) {
      Text(this.visibleBestScore > 0 ? `${this.visibleBestScore}` : '-')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_INK)
      Text('最佳')
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
  private AverageStatTile() {
    Column({ space: 3 }) {
      Text(this.visibleAverageScore > 0 ? `${this.visibleAverageScore}` : '-')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_INK)
      Text('平均')
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
  private LevelSelector() {
    Row({ space: 8 }) {
      ForEach(LEVEL_FILTERS, (level: string) => {
        Button(level)
          .height(38)
          .layoutWeight(1)
          .fontSize(13)
          .fontWeight(this.selectedLevel === level ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selectedLevel === level ? Color.White : COLOR_INK)
          .backgroundColor(this.selectedLevel === level ? COLOR_BLUE : COLOR_CARD)
          .borderRadius(6)
          .border({ width: 1, color: this.selectedLevel === level ? COLOR_BLUE : COLOR_LINE })
          .enabled(this.canChangeSentence())
          .onClick(() => {
            this.selectLevel(level);
          })
      }, (level: string) => level)
    }
    .width('100%')
  }

  @Builder
  private SentenceCard() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Text(this.focusLabel(this.sentence.focus))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY_DARK)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(COLOR_WARN_BG)
          .borderRadius(14)
        Blank()
        Button(this.refreshSentenceButtonText())
          .height(30)
          .width(88)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.canRefreshSentence() ? COLOR_BLUE : COLOR_MUTED)
          .backgroundColor('#F3EDE2')
          .borderRadius(6)
          .border({ width: 1, color: COLOR_LINE })
          .enabled(this.canRefreshSentence())
          .onClick(() => {
            void this.refreshSentence();
          })
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

      Text('自然读出句子，注意清晰度、节奏和上方标出的练习重点。')
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
        Text(this.errorMessage || '需要麦克风权限才能录制你的跟读音频。')
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
              Text('分')
                .fontSize(11)
                .fontColor(COLOR_MUTED)
            }
          }

          Column({ space: 9 }) {
            this.ScoreRow('流利度', this.result.fluencyScore, COLOR_BLUE)
            this.ScoreRow('发音', this.result.pronunciationScore, COLOR_GOOD)
            this.ScoreRow('语调', this.result.intonationScore, COLOR_PRIMARY)
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

        this.LanguageFeedbackPanel()

        Column({ space: 8 }) {
          Button(this.playbackButtonText())
            .height(48)
            .width('100%')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_INK)
            .backgroundColor(this.playbackButtonColor())
            .borderRadius(6)
            .enabled(this.canUsePlaybackButton())
            .onClick(() => {
              void this.togglePlayback();
            })

          if (this.isPlaybackLoading) {
            Text('首次播放需要先缓存音频，请稍等。')
              .fontSize(12)
              .fontColor(COLOR_MUTED)
              .textAlign(TextAlign.Center)
              .width('100%')
          }
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .backgroundColor(COLOR_CARD)
      .borderRadius(8)
      .border({ width: 1, color: COLOR_LINE })
      .width('100%')
    } else {
      Column({ space: 10 }) {
        Text('反馈会显示在这里')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_INK)
        Text('录音完成后，声练英语会检查清晰度、流利度和语调。')
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
  private CoachPanel() {
    if (this.isLoadingCoach || this.coachAction || this.coachErrorMessage.length > 0) {
      Column({ space: 12 }) {
        Row() {
          Text('AI 教练建议')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_INK)
          Blank()
          Text(this.isLoadingCoach ? '规划中' : this.coachSourceLabel())
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.coachAction?.source === 'fallback' ? COLOR_PRIMARY_DARK : COLOR_BLUE)
        }
        .width('100%')

        if (this.isLoadingCoach) {
          Text('正在结合本次表现和最近训练记录，规划下一步练习。')
            .fontSize(14)
            .lineHeight(20)
            .fontColor(COLOR_MUTED)
            .width('100%')
        } else if (this.coachAction) {
          Row() {
            Text(this.coachSourceLabel())
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.coachAction.source === 'fallback' ? COLOR_PRIMARY_DARK : COLOR_BLUE)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor(this.coachAction.source === 'fallback' ? COLOR_WARN_BG : '#E8F0F3')
              .borderRadius(12)
            Blank()
          }
          .width('100%')

          Text(this.coachAction.summary)
            .fontSize(14)
            .lineHeight(20)
            .fontColor(COLOR_INK)
            .width('100%')

          Text(this.coachAction.reason)
            .fontSize(13)
            .lineHeight(19)
            .fontColor(COLOR_MUTED)
            .width('100%')

          Column({ space: 6 }) {
            ForEach(this.coachAction.tips, (tip: string) => {
              Text(`- ${tip}`)
                .fontSize(13)
                .lineHeight(18)
                .fontColor(COLOR_INK)
                .width('100%')
            }, (tip: string) => tip)
          }
          .width('100%')

          Column({ space: 5 }) {
            Text('下一句')
              .fontSize(11)
              .fontColor(COLOR_MUTED)
            Text(this.coachAction.nextSentence.text)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .lineHeight(21)
              .fontColor(COLOR_INK)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .backgroundColor('#F6F0E5')
          .borderRadius(6)
          .width('100%')

          if (this.coachAction.fallbackReason && this.coachAction.source !== 'model') {
            Text(this.coachAction.fallbackReason)
              .fontSize(11)
              .lineHeight(16)
              .fontColor(COLOR_MUTED)
              .width('100%')
          }
        } else {
          Text(this.coachErrorMessage)
            .fontSize(13)
            .lineHeight(18)
            .fontColor(COLOR_PRIMARY_DARK)
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding(18)
      .backgroundColor(COLOR_CARD)
      .borderRadius(8)
      .border({ width: 1, color: COLOR_LINE })
      .width('100%')
    }
  }

  @Builder
  private LanguageFeedbackPanel() {
    if (this.result) {
      Column({ space: 10 }) {
        Row() {
          Text('语言优化')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_INK)
          Blank()
          Text('AI')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_BLUE)
        }
        .width('100%')

        this.LanguageSuggestionRow('语法纠正', this.result.languageFeedback.grammarCorrection)
        this.LanguageSuggestionRow('地道表达', this.result.languageFeedback.betterExpression)

        Text(this.result.languageFeedback.explanation)
          .fontSize(13)
          .lineHeight(18)
          .fontColor(COLOR_MUTED)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .backgroundColor('#F6F0E5')
      .borderRadius(6)
      .width('100%')
    }
  }

  @Builder
  private LanguageSuggestionRow(label: string, text: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(11)
        .fontColor(COLOR_MUTED)
      Text(text)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_INK)
        .lineHeight(20)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
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
        Text('建议')
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
      Button('重练')
        .height(48)
        .layoutWeight(1)
        .fontSize(15)
        .fontColor(COLOR_INK)
        .backgroundColor('#EAE2D3')
        .borderRadius(6)
        .enabled(this.canChangeSentence())
        .onClick(() => {
          this.resetAttempt();
        })

      Button(this.nextButtonText())
        .height(48)
        .layoutWeight(1)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor(COLOR_GOOD)
        .borderRadius(6)
        .enabled(this.canChangeSentence())
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
      this.errorMessage = '请允许麦克风权限后再开始口语练习。';
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
      this.errorMessage = `录音无法开始：${this.formatError(err)}`;
    }
  }

  private async stopRecordingAndEvaluate(): Promise<void> {
    try {
      this.stopTimer();
      this.stage = 'uploading';
      const recording: RecordingResult = await this.recorder!.stop();
      this.stage = 'evaluating';
      const evaluatedSentence = this.sentence;
      const evaluation = await TrainingApi.evaluate(evaluatedSentence, recording);
      this.result = evaluation;
      this.recordScore(evaluation.overallScore);
      this.stage = 'complete';
      await this.saveHistoryAndLoadCoach(evaluatedSentence, evaluation);
    } catch (err) {
      this.stage = 'error';
      this.errorMessage = `评估失败：${this.formatError(err)}`;
    }
  }

  private async togglePlayback(): Promise<void> {
    if (!this.result) {
      return;
    }
    if (!this.hasReferenceAudio()) {
      return;
    }
    if (this.isPlaybackLoading) {
      return;
    }
    if (this.isPlaying) {
      await this.playback?.pause();
      this.isPlaying = false;
      return;
    }
    try {
      this.isPlaybackLoading = true;
      await this.playback?.play(this.result.referenceAudioUrl);
      this.isPlaybackLoading = false;
      this.isPlaying = true;
    } catch (err) {
      this.errorMessage = `示范音频无法播放：${this.formatError(err)}`;
      this.isPlaybackLoading = false;
      this.isPlaying = false;
    }
  }

  private formatError(err: Error | Object | string): string {
    if (err instanceof Error) {
      return err.message;
    }
    return JSON.stringify(err);
  }

  private nextSentence(): void {
    if (!this.canChangeSentence()) {
      return;
    }

    const nextIndex = this.findNextSentenceIndex(this.sentenceIndex);
    this.sentenceIndex = nextIndex;
    this.sentence = this.coachAction ? this.coachAction.nextSentence : TRAINING_SENTENCES[nextIndex];
    this.resetAttempt();
    this.refreshVisibleStats();
  }

  private async refreshSentence(): Promise<void> {
    if (!this.canRefreshSentence()) {
      return;
    }

    this.isRefreshingSentence = true;
    this.errorMessage = '';
    try {
      this.sentence = await TrainingApi.refreshSentence(this.selectedLevel, this.sentence.text);
      this.resetAttempt();
    } catch (_) {
      const nextIndex = this.findRandomSentenceIndex(this.sentenceIndex);
      this.sentenceIndex = nextIndex;
      this.sentence = TRAINING_SENTENCES[nextIndex];
      this.resetAttempt();
    } finally {
      this.isRefreshingSentence = false;
    }
  }

  private selectLevel(level: string): void {
    if (!this.canChangeSentence()) {
      return;
    }

    if (this.selectedLevel === level) {
      return;
    }

    this.selectedLevel = level;
    this.refreshVisibleStats();
    const nextIndex = this.findFirstSentenceIndex(level);
    this.sentenceIndex = nextIndex;
    this.sentence = TRAINING_SENTENCES[nextIndex];
    this.resetAttempt();
  }

  private resetAttempt(): void {
    this.stopTimer();
    this.stage = 'idle';
    this.elapsedSeconds = 0;
    this.result = undefined;
    this.errorMessage = '';
    this.coachAction = undefined;
    this.coachErrorMessage = '';
    this.isPlaying = false;
    this.isPlaybackLoading = false;
    this.playback?.release();
  }

  private recordScore(score: number): void {
    this.totalCompletedCount += 1;
    this.totalScoreTotal += score;
    this.totalBestScore = Math.max(this.totalBestScore, score);

    const scoreLevel = this.selectedLevel === LEVEL_ALL ? this.sentence.level : this.selectedLevel;
    if (scoreLevel === 'A2') {
      this.a2CompletedCount += 1;
      this.a2ScoreTotal += score;
      this.a2BestScore = Math.max(this.a2BestScore, score);
      this.refreshVisibleStats();
      return;
    }

    if (scoreLevel === 'B1') {
      this.b1CompletedCount += 1;
      this.b1ScoreTotal += score;
      this.b1BestScore = Math.max(this.b1BestScore, score);
      this.refreshVisibleStats();
      return;
    }

    if (scoreLevel === 'B2') {
      this.b2CompletedCount += 1;
      this.b2ScoreTotal += score;
      this.b2BestScore = Math.max(this.b2BestScore, score);
    }
    this.refreshVisibleStats();
  }

  private async loadTrainingHistory(context: Context): Promise<void> {
    try {
      this.recentHistory = await TrainingHistoryService.load(context);
    } catch (_) {
      this.recentHistory = [];
    }
  }

  private async saveHistoryAndLoadCoach(sentence: TrainingSentence, result: EvaluationResult): Promise<void> {
    const context = getContext(this) as Context;
    try {
      this.recentHistory = await TrainingHistoryService.append(context, sentence, result);
    } catch (_) {
      // Training can continue even if local memory fails.
    }

    this.isLoadingCoach = true;
    this.coachAction = undefined;
    this.coachErrorMessage = '';
    try {
      this.coachAction = await TrainingApi.coachNextAction(sentence, result, this.recentHistory, this.selectedLevel);
    } catch (err) {
      this.coachErrorMessage = `教练建议暂时不可用：${this.formatError(err)}`;
    } finally {
      this.isLoadingCoach = false;
    }
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
        return '正在聆听';
      case 'uploading':
        return '正在上传录音';
      case 'evaluating':
        return '正在分析发音';
      case 'complete':
        return '反馈已生成';
      case 'permissionDenied':
        return '麦克风未授权';
      case 'error':
        return '需要再试一次';
      default:
        return '准备开始练习';
    }
  }

  private primaryButtonText(): string {
    if (this.stage === 'recording') {
      return '停止';
    }
    if (this.stage === 'uploading' || this.stage === 'evaluating') {
      return '分析中';
    }
    return '录音';
  }

  private nextButtonText(): string {
    if (this.isLoadingCoach) {
      return '规划中';
    }
    return this.coachAction ? '智能下一句' : '下一句';
  }

  private coachSourceLabel(): string {
    if (!this.coachAction) {
      return 'Agent';
    }
    if (this.coachAction.source === 'fallback') {
      return '兜底';
    }
    if (this.coachAction.source === 'mixed') {
      return '混合';
    }
    return 'Agent';
  }

  private refreshSentenceButtonText(): string {
    return this.isRefreshingSentence ? '刷新中' : '刷新句子';
  }

  private playbackButtonText(): string {
    if (!this.hasReferenceAudio()) {
      return '暂无示范音频';
    }
    if (this.isPlaybackLoading) {
      return '正在加载示范音频';
    }
    return this.isPlaying ? '暂停示范音频' : '播放示范音频';
  }

  private playbackButtonColor(): string {
    if (this.isPlaybackLoading) {
      return '#E0D6C6';
    }
    return this.hasReferenceAudio() ? '#EAE2D3' : '#F3EDE2';
  }

  private canUsePlaybackButton(): boolean {
    return this.hasReferenceAudio() && !this.isPlaybackLoading;
  }

  private hasReferenceAudio(): boolean {
    if (!this.result) {
      return false;
    }
    return this.result.referenceAudioUrl.length > 0;
  }

  private findFirstSentenceIndex(level: string): number {
    for (let index = 0; index < TRAINING_SENTENCES.length; index += 1) {
      if (this.matchesLevel(TRAINING_SENTENCES[index], level)) {
        return index;
      }
    }
    return 0;
  }

  private findNextSentenceIndex(currentIndex: number): number {
    for (let offset = 1; offset <= TRAINING_SENTENCES.length; offset += 1) {
      const nextIndex = (currentIndex + offset) % TRAINING_SENTENCES.length;
      if (this.matchesLevel(TRAINING_SENTENCES[nextIndex], this.selectedLevel)) {
        return nextIndex;
      }
    }
    return 0;
  }

  private findRandomSentenceIndex(currentIndex: number): number {
    const candidates: number[] = [];
    for (let index = 0; index < TRAINING_SENTENCES.length; index += 1) {
      if (this.matchesLevel(TRAINING_SENTENCES[index], this.selectedLevel) && index !== currentIndex) {
        candidates.push(index);
      }
    }
    if (candidates.length === 0) {
      return this.findNextSentenceIndex(currentIndex);
    }
    return candidates[Math.floor(Math.random() * candidates.length)];
  }

  private currentSentencePosition(): number {
    let position = 0;
    for (let index = 0; index < TRAINING_SENTENCES.length; index += 1) {
      if (this.matchesLevel(TRAINING_SENTENCES[index], this.selectedLevel)) {
        position += 1;
      }
      if (index === this.sentenceIndex) {
        return Math.max(position, 1);
      }
    }
    return 1;
  }

  private filteredSentenceCount(): number {
    let count = 0;
    for (let index = 0; index < TRAINING_SENTENCES.length; index += 1) {
      if (this.matchesLevel(TRAINING_SENTENCES[index], this.selectedLevel)) {
        count += 1;
      }
    }
    return Math.max(count, 1);
  }

  private displayCompletedCount(): number {
    if (this.selectedLevel === 'A2') {
      return this.a2CompletedCount;
    }
    if (this.selectedLevel === 'B1') {
      return this.b1CompletedCount;
    }
    if (this.selectedLevel === 'B2') {
      return this.b2CompletedCount;
    }
    return this.totalCompletedCount;
  }

  private displayBestScore(): number {
    if (this.selectedLevel === 'A2') {
      return this.a2BestScore;
    }
    if (this.selectedLevel === 'B1') {
      return this.b1BestScore;
    }
    if (this.selectedLevel === 'B2') {
      return this.b2BestScore;
    }
    return this.totalBestScore;
  }

  private displayAverageScore(): number {
    const completedCount = this.displayCompletedCount();
    if (completedCount === 0) {
      return 0;
    }
    if (this.selectedLevel === 'A2') {
      return Math.round(this.a2ScoreTotal / completedCount);
    }
    if (this.selectedLevel === 'B1') {
      return Math.round(this.b1ScoreTotal / completedCount);
    }
    if (this.selectedLevel === 'B2') {
      return Math.round(this.b2ScoreTotal / completedCount);
    }
    return Math.round(this.totalScoreTotal / completedCount);
  }

  private refreshVisibleStats(): void {
    this.visibleCompletedCount = this.displayCompletedCount();
    this.visibleBestScore = this.displayBestScore();
    this.visibleAverageScore = this.displayAverageScore();
  }

  private matchesLevel(sentence: TrainingSentence, level: string): boolean {
    return level === LEVEL_ALL || sentence.level === level;
  }

  private focusLabel(focus: string): string {
    switch (focus) {
      case 'linking sounds':
        return '连读';
      case 'sentence rhythm':
        return '句子节奏';
      case 'question intonation':
        return '疑问句语调';
      case 'past tense endings':
        return '过去式词尾';
      case 'word stress':
        return '单词重音';
      case 'polite tone':
        return '礼貌语气';
      case 'vowel clarity':
        return '元音清晰度';
      case 'natural pauses':
        return '自然停顿';
      case 'multi-syllable words':
        return '多音节词';
      case 'connected speech':
        return '连贯表达';
      default:
        return focus;
    }
  }

  private isBusy(): boolean {
    return this.stage === 'uploading' || this.stage === 'evaluating' || this.isRefreshingSentence || this.isLoadingCoach;
  }

  private canChangeSentence(): boolean {
    return this.stage !== 'recording' && !this.isBusy() && !this.isPlaybackLoading;
  }

  private canRefreshSentence(): boolean {
    return this.canChangeSentence();
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
