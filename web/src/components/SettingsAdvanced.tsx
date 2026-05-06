import { useEffect, useState } from "react";
import clsx from "clsx";
import type { Capabilities, JobSubmitSettings } from "../api/types";
import { SettingsIcon, ChevronDownIcon } from "../lib/icons";

interface Props {
  capabilities: Capabilities;
  value: JobSubmitSettings;
  onChange: (next: JobSubmitSettings) => void;
}

export function SettingsAdvanced({ capabilities, value, onChange }: Props) {
  const [open, setOpen] = useState(false);

  const update = (patch: Partial<JobSubmitSettings>) => {
    onChange({ ...value, ...patch });
  };

  useEffect(() => {
    const codec = capabilities.codecs.find((c) => c.id === value.codec);
    if (codec && !codec.compatibleContainers.includes(value.container)) {
      onChange({ ...value, container: codec.compatibleContainers[0] ?? value.container });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value.codec, capabilities.codecs]);

  return (
    <div className="surface-card overflow-hidden">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="w-full px-5 py-3.5 flex items-center justify-between hover:bg-[var(--surface-2)] transition-colors"
        aria-expanded={open}
      >
        <div className="flex items-center gap-2.5">
          <SettingsIcon size={16} className="text-zinc-400" />
          <span className="text-sm font-medium text-zinc-200">Advanced settings</span>
        </div>
        <ChevronDownIcon
          size={16}
          className={clsx("text-zinc-500 transition-transform duration-200", open && "rotate-180")}
        />
      </button>
      {open && (
        <div className="px-5 pb-5 pt-2 space-y-5 border-t border-white/[0.06] animate-fade-in-up">
          <Field
            label="Segment minutes"
            hint={`Range ${capabilities.segmentMinutes.min}–${capabilities.segmentMinutes.max} min`}
          >
            <input
              type="number"
              min={capabilities.segmentMinutes.min}
              max={capabilities.segmentMinutes.max}
              value={value.segmentMinutes}
              onChange={(e) => update({ segmentMinutes: Number(e.target.value) })}
              className="surface-input px-3 py-2 w-32 text-sm"
            />
          </Field>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <Field label="Codec">
              <select
                value={value.codec}
                onChange={(e) => update({ codec: e.target.value })}
                className="surface-input px-3 py-2 w-full text-sm"
              >
                {capabilities.codecs.map((c) => (
                  <option key={c.id} value={c.id}>{c.displayName}</option>
                ))}
              </select>
            </Field>
            <Field label="Container">
              <select
                value={value.container}
                onChange={(e) => update({ container: e.target.value })}
                className="surface-input px-3 py-2 w-full text-sm"
              >
                {capabilities.containers
                  .filter((c) => {
                    const codec = capabilities.codecs.find((cc) => cc.id === value.codec);
                    return !codec || codec.compatibleContainers.includes(c.id);
                  })
                  .map((c) => (
                    <option key={c.id} value={c.id}>{c.displayName}</option>
                  ))}
              </select>
            </Field>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <Field label="Sample rate">
              <select
                value={value.sampleRate}
                onChange={(e) => update({ sampleRate: Number(e.target.value) })}
                className="surface-input px-3 py-2 w-full text-sm"
              >
                {capabilities.sampleRates.map((sr) => (
                  <option key={sr} value={sr}>{sr.toLocaleString()} Hz</option>
                ))}
              </select>
            </Field>
            <Field label="Channels">
              <select
                value={value.channels}
                onChange={(e) => update({ channels: Number(e.target.value) })}
                className="surface-input px-3 py-2 w-full text-sm"
              >
                {capabilities.channelCounts.map((c) => (
                  <option key={c} value={c}>{c === 1 ? "Mono" : "Stereo"}</option>
                ))}
              </select>
            </Field>
            <Field label="Bitrate">
              <input
                type="text"
                value={value.bitrate}
                disabled={!capabilities.codecs.find((c) => c.id === value.codec)?.bitrateApplicable}
                onChange={(e) => update({ bitrate: e.target.value })}
                className="surface-input px-3 py-2 w-full text-sm font-mono"
                placeholder="48k"
              />
            </Field>
          </div>

          <Field label="Filename prefix">
            <input
              type="text"
              value={value.filenamePrefix ?? ""}
              onChange={(e) => update({ filenamePrefix: e.target.value })}
              className="surface-input px-3 py-2 w-full text-sm font-mono"
              placeholder="meeting"
            />
          </Field>

          <div className="space-y-2.5">
            <Toggle
              label="Reset timestamps in segments"
              hint="Recommended for transcription pipelines."
              checked={value.resetTimestamps ?? true}
              onChange={(v) => update({ resetTimestamps: v })}
            />
            <Toggle
              label="Loudness normalization"
              hint="Apply EBU R128 loudnorm filter."
              checked={value.loudnessNormalizationEnabled ?? false}
              onChange={(v) => update({ loudnessNormalizationEnabled: v })}
            />
          </div>

          <Field
            label="Extra ffmpeg arguments"
            hint="Quoted strings supported. Power-user only."
          >
            <input
              type="text"
              value={value.extraFFmpegArguments ?? ""}
              onChange={(e) => update({ extraFFmpegArguments: e.target.value })}
              className="surface-input px-3 py-2 w-full font-mono text-xs"
              placeholder='-map_metadata -1'
            />
          </Field>
        </div>
      )}
    </div>
  );
}

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <div className="flex items-baseline justify-between mb-1.5">
        <span className="text-[10px] uppercase tracking-[0.2em] text-zinc-500 font-medium">{label}</span>
        {hint && <span className="text-[10px] text-zinc-600">{hint}</span>}
      </div>
      {children}
    </label>
  );
}

function Toggle({
  label,
  hint,
  checked,
  onChange
}: {
  label: string;
  hint?: string;
  checked: boolean;
  onChange: (next: boolean) => void;
}) {
  return (
    <button
      type="button"
      onClick={() => onChange(!checked)}
      className="flex items-center justify-between w-full text-left py-1.5 group"
      role="switch"
      aria-checked={checked}
    >
      <span className="flex-1">
        <span className="block text-sm text-zinc-200 group-hover:text-white transition-colors">{label}</span>
        {hint && <span className="block text-xs text-zinc-500">{hint}</span>}
      </span>
      <span className="toggle-switch" data-state={checked ? "on" : "off"} aria-hidden="true" />
    </button>
  );
}
