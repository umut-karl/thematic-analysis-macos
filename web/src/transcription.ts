import type { ParticipantDetails, TranscriptSegment } from './domain';
import { emptyDetails } from './domain';

export const AUDIO_EXTENSIONS = ['mp3', 'mp4', 'mpeg', 'mpga', 'm4a', 'wav', 'webm', 'flac', 'ogg'];
export const MAX_AUDIO_SIZE = 25 * 1024 * 1024;
export const TRANSCRIPTION_MODEL = 'gpt-4o-transcribe-diarize';

export interface DiarizedSegment { speaker: string; start: number; end: number; text: string }
export interface TranscriptionResult { model: string; segments: DiarizedSegment[] }
export interface OpenAIStatus { configured: boolean; source: 'environment' | 'native-settings' | null }

export async function openAIStatus(): Promise<OpenAIStatus> {
  const response = await fetch('/api/openai/status', { cache: 'no-store' });
  if (!response.ok) throw new Error('OpenAI ayar durumu okunamadı. Web sunucusunu yeniden başlatın.');
  return response.json();
}

export async function saveOpenAIKey(apiKey: string): Promise<OpenAIStatus> {
  const response = await fetch('/api/openai/key', {
    method: 'PUT', headers: { 'Content-Type': 'application/json', 'X-Tematik-Analiz': 'local' },
    body: JSON.stringify({ apiKey }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(typeof payload.error === 'string' ? payload.error : 'API anahtarı kaydedilemedi.');
  return payload as OpenAIStatus;
}

export async function deleteOpenAIKey(): Promise<OpenAIStatus> {
  const response = await fetch('/api/openai/key', { method: 'DELETE', headers: { 'X-Tematik-Analiz': 'local' } });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(typeof payload.error === 'string' ? payload.error : 'API anahtarı silinemedi.');
  return payload as OpenAIStatus;
}

export async function transcribeAudio(file: File, signal?: AbortSignal): Promise<TranscriptionResult> {
  const extension = file.name.split('.').pop()?.toLowerCase() || '';
  if (!AUDIO_EXTENSIONS.includes(extension)) throw new Error('Desteklenmeyen ses biçimi. MP3, MP4, MPEG, MPGA, M4A, WAV, WEBM, FLAC veya OGG seçin.');
  if (file.size > MAX_AUDIO_SIZE) throw new Error('Ses dosyası 25 MB sınırını aşıyor.');
  if (!file.size) throw new Error('Ses dosyası boş.');
  const response = await fetch('/api/openai/transcriptions', {
    method: 'POST', body: file, signal,
    headers: { 'Content-Type': file.type || 'application/octet-stream', 'X-File-Name-Base64': utf8Base64(file.name) },
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(typeof payload.error === 'string' ? payload.error : `Ses transkripsiyonu başarısız (HTTP ${response.status}).`);
  if (!Array.isArray(payload.segments) || !payload.segments.length) throw new Error('OpenAI geçerli bir transkript döndürmedi.');
  return payload as TranscriptionResult;
}

export function speakersOf(result: TranscriptionResult): string[] {
  return [...new Set(result.segments.map((segment) => segment.speaker))];
}

export function suggestedSpeakerNames(result: TranscriptionResult, participant: string): Record<string, string> {
  return Object.fromEntries(speakersOf(result).map((speaker, index) => [speaker, index === 0 ? 'Görüşmeci' : index === 1 ? participant.trim() : `Konuşmacı ${index + 1}`]));
}

export function diarizedTranscriptSegments(result: TranscriptionResult, speakerNames: Record<string, string>): TranscriptSegment[] {
  return result.segments.flatMap((source, index) => {
    const text = source.text.trim();
    if (!text) return [];
    return [{
      id: crypto.randomUUID(), order: index + 1, part: null,
      speaker: speakerNames[source.speaker]?.trim() || source.speaker,
      start: displayAudioTime(source.start, 'down'), end: displayAudioTime(source.end, 'up'), text,
    }];
  });
}

export function detailsWithTranscriptionProvenance(
  details: ParticipantDetails,
  fileName: string,
  model: string,
): ParticipantDetails {
  const provenance = `Ses transkripsiyonu · Model: ${model} · Kaynak: ${fileName}`;
  return { ...emptyDetails(), ...details, notes: details.notes.trim() ? `${details.notes.trim()}\n${provenance}` : provenance };
}

export function displayAudioTime(seconds: number, rounding: 'up' | 'down' = 'down'): string {
  const value = Math.max(0, Math[rounding === 'up' ? 'ceil' : 'floor'](seconds));
  const hours = Math.floor(value / 3600);
  const minutes = Math.floor((value % 3600) / 60);
  const remainder = value % 60;
  return hours > 0
    ? [hours, minutes, remainder].map((part) => String(part).padStart(2, '0')).join(':')
    : [minutes, remainder].map((part) => String(part).padStart(2, '0')).join(':');
}

function utf8Base64(value: string): string {
  const bytes = new TextEncoder().encode(value);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
