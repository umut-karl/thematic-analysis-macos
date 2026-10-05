import { describe, expect, it } from 'vitest';
import type { AnalysisProject, Interview } from './domain';
import { migrateLegacyPrototype, saveCodingUnit, themePathName, themeUsage, validateProject } from './domain';

const IDs = {
  root: '00000000-0000-4000-8000-000000000001',
  child: '00000000-0000-4000-8000-000000000002',
  interview: '00000000-0000-4000-8000-000000000003',
  segment1: '00000000-0000-4000-8000-000000000004',
  segment2: '00000000-0000-4000-8000-000000000005',
};
const themeRoot = { id: IDs.root, name: 'Güven', parentID: null, colorIndex: 0, note: null };
const themeChild = { id: IDs.child, name: 'Denetim', parentID: IDs.root, colorIndex: 0, note: null };
const interview: Interview = {
  id: IDs.interview, name: 'Görüşme 1', participant: 'Ayşe', participantDetails: null,
  importedAt: '2026-08-29T10:00:00Z',
  segments: [
    { id: IDs.segment1, order: 1, part: 1, speaker: 'Ayşe', start: '00:01', end: '00:03', text: 'İlk ifade.' },
    { id: IDs.segment2, order: 2, part: 1, speaker: 'Ayşe', start: '00:04', end: '00:06', text: 'İkinci ifade.' },
  ], codingUnits: [],
};
const project: AnalysisProject = { name: 'Test', interviews: [interview], themes: [themeRoot, themeChild], updatedAt: '2026-08-29T10:00:00Z' };

describe('native-compatible domain', () => {
  it('validates the same project shape used by the Swift app', () => {
    expect(validateProject(JSON.parse(JSON.stringify(project)))).toEqual(project);
  });

  it('stores selected segments, multiple themes, and memo in a coding unit', () => {
    const saved = saveCodingUnit(interview, [IDs.segment2, IDs.segment1], [IDs.root, IDs.child], 'Analitik not');
    expect(saved.codingUnits).toHaveLength(1);
    expect(saved.codingUnits[0].segmentIDs).toEqual([IDs.segment1, IDs.segment2]);
    expect(saved.codingUnits[0].themeIDs).toEqual([IDs.root, IDs.child]);
    expect(saved.codingUnits[0].memo).toBe('Analitik not');
  });

  it('merges an additional theme into the same coding unit without duplication', () => {
    const first = saveCodingUnit(interview, [IDs.segment1], [IDs.root], 'İlk not');
    const second = saveCodingUnit(first, [IDs.segment1], [IDs.child], '');
    expect(second.codingUnits).toHaveLength(1);
    expect(second.codingUnits[0].themeIDs).toEqual([IDs.root, IDs.child]);
    expect(second.codingUnits[0].memo).toBe('İlk not');
  });

  it('rolls descendant assignments into parent analytics', () => {
    const coded = saveCodingUnit(interview, [IDs.segment1], [IDs.child], '');
    const usage = themeUsage({ ...project, interviews: [coded] });
    expect(usage.find((item) => item.theme.id === IDs.root)?.codingCount).toBe(1);
    expect(themePathName(project, IDs.child)).toBe('Güven › Denetim');
  });

  it('migrates a legacy prototype backup without inventing transcript or coding data', () => {
    const migrated = migrateLegacyPrototype({ name: 'Eski', participants: [{ id: 'p1', name: 'Ayşe', rows: 42, codes: 12 }] });
    expect(migrated?.interviews[0].segments).toEqual([]);
    expect(migrated?.interviews[0].codingUnits).toEqual([]);
    expect(() => validateProject(migrated)).not.toThrow();
    expect(migrated?.interviews[0].id).toMatch(/^[0-9a-f-]{36}$/i);
  });

  it('rejects identifiers that the native UUID decoder cannot open', () => {
    expect(() => validateProject({ ...project, interviews: [{ ...interview, id: 'interview-1' }] })).toThrow();
  });
});
