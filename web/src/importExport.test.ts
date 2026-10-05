import JSZip from 'jszip';
import { describe, expect, it } from 'vitest';
import { parseTranscript, readProjectBackup } from './importExport';

describe('imports and native backup compatibility', () => {
  it('maps Turkish CSV headers and quoted cells', async () => {
    const csv = '\uFEFFSıra,Konuşmacı,Başlangıç,Bitiş,Metin\n1,Ayşe,00:01,00:03,"Virgüllü, ifade"\n2,Araştırmacı,00:04,00:06,Soru';
    const file = new File([csv], 'transkript.csv', { type: 'text/csv' });
    const segments = await parseTranscript(file);
    expect(segments).toHaveLength(2);
    expect(segments[0].text).toBe('Virgüllü, ifade');
    expect(segments[1].speaker).toBe('Araştırmacı');
  });

  it('opens the JSON project shape exported by the Swift app', async () => {
    const project = { name: 'Native', interviews: [], themes: [], updatedAt: '2026-08-29T10:00:00Z' };
    const result = await readProjectBackup(new File([JSON.stringify(project)], 'Proje-Verisi.json'));
    expect(result.project).toEqual(project);
    expect(result.migrated).toBe(false);
  });

  it('opens a native ZIP archive containing Proje-Verisi.json', async () => {
    const project = { name: 'Native ZIP', interviews: [], themes: [], updatedAt: '2026-08-29T10:00:00Z' };
    const zip = new JSZip(); zip.file('Native ZIP/Proje-Verisi.json', JSON.stringify(project));
    const bytes = await zip.generateAsync({ type: 'uint8array' });
    const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
    const result = await readProjectBackup(new File([buffer], 'Native.zip', { type: 'application/zip' }));
    expect(result.project.name).toBe('Native ZIP');
  });

  it('rejects an unrelated JSON file', async () => {
    await expect(readProjectBackup(new File(['{"hello":"world"}'], 'invalid.json'))).rejects.toThrow(/şemasına/);
  });
});
