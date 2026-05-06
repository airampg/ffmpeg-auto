import { useEffect, useState } from "react";
import type { Capabilities, JobSubmitSettings } from "../api/types";

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
  }, [value.codec, capabilities.codecs]);

  return (
    <div className="border border-zinc-800 rounded">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="w-full px-3 py-2 text-left text-sm font-medium text-zinc-300 hover:bg-zinc-900 flex items-center justify-between"
      >
        <span>Advanced settings</span>
        <span className="text-xs text-zinc-500">{open ? "hide" : "show"}</span>
      </button>
      {open && (
        <div className="p-4 space-y-4 border-t border-zinc-800 text-sm">
          <Field label="Segment minutes">
            <input
              type="number"
              min={capabilities.segmentMinutes.min}
              max={capabilities.segmentMinutes.max}
              value={value.segmentMinutes}
              onChange={(e) => update({ segmentMinutes: Number(e.target.value) })}
              className="bg-zinc-900 border border-zinc-700 rounded px-2 py-1 w-24"
            />
            <span className="text-xs text-zinc-500 ml-2">
              ({capabilities.segmentMinutes.min}–{capabilities.segmentMinutes.max})
            </span>
          </Field>

          <div className="grid grid-cols-2 gap-3">
            <Field label="Codec">
              <select
                value={value.codec}
                onChange={(e) => update({ codec: e.target.value })}
                className="bg-zinc-900 border border-zinc-700 rounded px-2 py-1 w-full"
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
                className="bg-zinc-900 border border-zinc-700 rounded px-2 py-1 w-full"
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

          <div className="grid grid-cols-3 gap-3">
            <Field label="Sample rate">
              <select
                value={value.sampleRate}
                onChange={(e) => update({ sampleRate: Number(e.target.value) })}
                className="bg-zinc-900 border border-zinc-700 rounded px-2 py-1 w-full"
              >
                {capabilities.sampleRates.map((sr) => (
                  <option key={sr} value={sr}>{sr} Hz</option>
                ))}
              </select>
            </Field>
            <Field label="Channels">
              <select
                value={value.channels}
                onChange={(e) => update({ channels: Number(e.target.value) })}
                className="bg-zinc-900 border border-zinc-700 rounded px-2 py-1 w-full"
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
                className="bg-zinc-900 border border-zinc-700 rounded px-2 py-1 w-full disabled:opacity-50"
                placeholder="48k"
              />
            </Field>
          </div>

          <Field label="Filename prefix">
            <input
              type="text"
              value={value.filenamePrefix ?? ""}
              onChange={(e) => update({ filenamePrefix: e.target.value })}
              className="bg-zinc-900 border border-zinc-700 rounded px-2 py-1 w-full"
              placeholder="meeting"
            />
          </Field>

          <div className="flex gap-4 text-sm">
            <label className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={value.resetTimestamps ?? true}
                onChange={(e) => update({ resetTimestamps: e.target.checked })}
              />
              Reset timestamps
            </label>
            <label className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={value.loudnessNormalizationEnabled ?? false}
                onChange={(e) => update({ loudnessNormalizationEnabled: e.target.checked })}
              />
              Loudness normalization
            </label>
          </div>

          <Field label="Extra ffmpeg arguments">
            <input
              type="text"
              value={value.extraFFmpegArguments ?? ""}
              onChange={(e) => update({ extraFFmpegArguments: e.target.value })}
              className="bg-zinc-900 border border-zinc-700 rounded px-2 py-1 w-full font-mono text-xs"
              placeholder="(advanced; quoted strings supported)"
            />
          </Field>
        </div>
      )}
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="block text-xs uppercase tracking-wide text-zinc-500 mb-1">{label}</span>
      {children}
    </label>
  );
}
