export type JobStatus = "queued" | "running" | "succeeded" | "failed" | "cancelled";

export interface JobOutput {
  name: string;
  sizeBytes: number;
}

export interface JobProgress {
  percent: number | null;
  currentTimeSeconds: number | null;
  totalDurationSeconds: number | null;
}

export interface JobSummary {
  jobId: string;
  status: JobStatus;
  createdAt: string;
  startedAt: string | null;
  finishedAt: string | null;
  inputFilename: string;
}

export interface JobDetail {
  jobId: string;
  status: JobStatus;
  createdAt: string;
  startedAt: string | null;
  finishedAt: string | null;
  inputFilename: string;
  command: string | null;
  progress: JobProgress;
  outputCount: number | null;
  outputs: JobOutput[];
  errorMessage: string | null;
}

export interface JobsListResponse {
  jobs: JobSummary[];
}

export interface JobCreatedResponse {
  jobId: string;
  status: "queued";
}

export interface ApiErrorPayload {
  code: string;
  message: string;
}

export interface CodecOption {
  id: string;
  displayName: string;
  ffmpegName: string;
  compatibleContainers: string[];
  bitrateApplicable: boolean;
}

export interface ContainerOption {
  id: string;
  displayName: string;
  fileExtension: string;
}

export interface SegmentRange {
  min: number;
  max: number;
}

export interface DefaultSettings {
  codec: string;
  container: string;
  bitrate: string;
  sampleRate: number;
  channels: number;
  segmentMinutes: number;
  filenamePrefix: string;
  resetTimestamps: boolean;
  loudnessNormalizationEnabled: boolean;
}

export interface Capabilities {
  codecs: CodecOption[];
  containers: ContainerOption[];
  sampleRates: number[];
  channelCounts: number[];
  segmentMinutes: SegmentRange;
  collisionPolicies: string[];
  bitratePattern: string;
  defaultSettings: DefaultSettings;
}

export interface JobSubmitSettings {
  segmentMinutes: number;
  audioOnly?: boolean;
  codec: string;
  container: string;
  bitrate: string;
  sampleRate: number;
  channels: number;
  filenamePrefix?: string;
  resetTimestamps?: boolean;
  collisionPolicy?: string;
  loudnessNormalizationEnabled?: boolean;
  extraFFmpegArguments?: string;
}
