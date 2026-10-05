import { describe, expect, it } from 'vitest';
import { detailsWithTranscriptionProvenance, diarizedTranscriptSegments, displayAudioTime, suggestedSpeakerNames, type TranscriptionResult } from './transcription';
import { emptyDetails } from './domain';

const result: TranscriptionResult = {
  model: 'gpt-4o-transcribe-diarize',
  segments: [
    { speaker: 'A', start: 0.2, end: 4.1, text: ' Hoş geldiniz. ' },
    { speaker: 'B', start: 4.2, end: 65.3, text: 'Teşekkür ederim.' },
  ],
};

describe('audio transcription mapping', () => {
  it('suggests interviewer and participant names', () => {
    expect(suggestedSpeakerNames(result, 'Ayşe')).toEqual({ A: 'Görüşmeci', B: 'Ayşe' });
  });

  it('creates native-compatible timed transcript rows', () => {
    const segments = diarizedTranscriptSegments(result, { A: 'Araştırmacı', B: 'Ayşe' });
    expect(segments.map((item) => [item.speaker, item.start, item.end, item.text])).toEqual([
      ['Araştırmacı', '00:00', '00:05', 'Hoş geldiniz.'],
      ['Ayşe', '00:04', '01:06', 'Teşekkür ederim.'],
    ]);
  });

  it('formats hour-long audio and preserves provenance', () => {
    expect(displayAudioTime(3661.1, 'up')).toBe('01:01:02');
    const details = detailsWithTranscriptionProvenance({ ...emptyDetails(), notes: 'Araştırmacı notu' }, 'görüşme.m4a', result.model);
    expect(details.notes).toContain('Araştırmacı notu\nSes transkripsiyonu');
    expect(details.notes).toContain('görüşme.m4a');
  });
});
