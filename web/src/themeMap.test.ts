import { describe, expect, it } from 'vitest';
import type { AnalysisProject } from './domain';
import { createThemeMapLayout, themeEvidence } from './themeMap';

const ids = {
  rootA: '10000000-0000-4000-8000-000000000001', rootB: '10000000-0000-4000-8000-000000000002',
  child: '10000000-0000-4000-8000-000000000003', interview: '10000000-0000-4000-8000-000000000004',
  segment: '10000000-0000-4000-8000-000000000005', unit: '10000000-0000-4000-8000-000000000006',
};
const project: AnalysisProject = {
  name: 'Harita', updatedAt: '2026-08-29T10:00:00Z',
  themes: [
    { id: ids.rootA, name: 'A', parentID: null, colorIndex: 0, note: null },
    { id: ids.rootB, name: 'B', parentID: null, colorIndex: 1, note: null },
    { id: ids.child, name: 'Alt', parentID: ids.rootA, colorIndex: 0, note: null },
  ],
  interviews: [{
    id: ids.interview, name: 'Görüşme', participant: 'Ayşe', importedAt: '2026-08-29T10:00:00Z', participantDetails: null,
    segments: [{ id: ids.segment, order: 1, part: null, speaker: 'Ayşe', start: '00:01', end: '00:03', text: 'Kanıt.' }],
    codingUnits: [{ id: ids.unit, segmentIDs: [ids.segment], themeIDs: [ids.child], memo: 'Not', createdAt: '2026-08-29T10:00:00Z' }],
  }],
};

describe('theme map', () => {
  it('places alternating root branches on both sides of the center', () => {
    const layout = createThemeMapLayout(project, new Set());
    expect(layout.positions.get(ids.rootA)!.x).toBeLessThan(layout.center.x);
    expect(layout.positions.get(ids.rootB)!.x).toBeGreaterThan(layout.center.x);
    expect(layout.edges).toContainEqual({ parent: ids.rootA, child: ids.child, color: 0 });
  });

  it('hides descendants when a branch is collapsed', () => {
    const layout = createThemeMapLayout(project, new Set([ids.rootA]));
    expect(layout.positions.has(ids.child)).toBe(false);
    expect(layout.edges).toHaveLength(0);
  });

  it('rolls descendant evidence into its parent with assigned paths', () => {
    const evidence = themeEvidence(project, ids.rootA);
    expect(evidence).toHaveLength(1);
    expect(evidence[0].text).toBe('Kanıt.');
    expect(evidence[0].assignedPaths).toEqual(['A › Alt']);
  });
});
