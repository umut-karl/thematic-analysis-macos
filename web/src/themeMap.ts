import type { AnalysisProject, ThemeNode } from './domain';
import { childrenOf, isThemeDescendant, selectedText, themePathName } from './domain';

export interface ThemeMapEdge { parent: string; child: string; color: number }
export interface ThemeMapPosition { x: number; y: number }
export interface ThemeMapLayout {
  positions: Map<string, ThemeMapPosition>;
  visible: ThemeNode[];
  edges: ThemeMapEdge[];
  rootIDs: string[];
  center: ThemeMapPosition;
  width: number;
  height: number;
}
export interface ThemeEvidenceItem {
  interviewID: string;
  unitID: string;
  participant: string;
  interview: string;
  time: string;
  text: string;
  memo: string;
  assignedPaths: string[];
}

export function createThemeMapLayout(project: AnalysisProject, collapsed: Set<string>): ThemeMapLayout {
  const roots = childrenOf(project, null);
  const leftRoots = roots.filter((_, index) => index % 2 === 0);
  const rightRoots = roots.filter((_, index) => index % 2 === 1);
  const positions = new Map<string, ThemeMapPosition>();
  const edges: ThemeMapEdge[] = [];
  const visible: ThemeNode[] = [];
  const leftIDs: string[] = [];
  const rightIDs: string[] = [];

  function maximumDepth(node: ThemeNode, depth = 0): number {
    const children = collapsed.has(node.id) ? [] : childrenOf(project, node.id);
    return children.length ? Math.max(...children.map((child) => maximumDepth(child, depth + 1))) : depth;
  }

  const leftDepth = leftRoots.length ? Math.max(...leftRoots.map((root) => maximumDepth(root))) : 0;
  const rightDepth = rightRoots.length ? Math.max(...rightRoots.map((root) => maximumDepth(root))) : 0;
  const centerX = (leftDepth + 1) * 250 + 210;
  const rowHeight = 72;

  function place(node: ThemeNode, depth: number, direction: -1 | 1, cursor: { row: number }, sideIDs: string[]): number {
    visible.push(node); sideIDs.push(node.id);
    const children = collapsed.has(node.id) ? [] : childrenOf(project, node.id);
    let centerRow: number;
    if (!children.length) {
      centerRow = cursor.row;
      cursor.row += 1;
    } else {
      const childRows = children.map((child) => {
        edges.push({ parent: node.id, child: child.id, color: child.colorIndex });
        return place(child, depth + 1, direction, cursor, sideIDs);
      });
      centerRow = (childRows[0] + childRows.at(-1)!) / 2;
    }
    const x = direction < 0
      ? centerX - 240 - 190 - depth * 250
      : centerX + 240 + depth * 250;
    positions.set(node.id, { x, y: 24 + centerRow * rowHeight });
    return centerRow;
  }

  const leftCursor = { row: 0 };
  const rightCursor = { row: 0 };
  leftRoots.forEach((root) => place(root, 0, -1, leftCursor, leftIDs));
  rightRoots.forEach((root) => place(root, 0, 1, rightCursor, rightIDs));
  const totalRows = Math.max(leftCursor.row, rightCursor.row, 1);
  const leftShift = (totalRows - leftCursor.row) * rowHeight / 2;
  const rightShift = (totalRows - rightCursor.row) * rowHeight / 2;
  leftIDs.forEach((id) => { const position = positions.get(id); if (position) position.y += leftShift; });
  rightIDs.forEach((id) => { const position = positions.get(id); if (position) position.y += rightShift; });

  const rightEdge = centerX + 240 + rightDepth * 250 + 190;
  const width = Math.max(rightEdge + 40, centerX + 250);
  const height = Math.max(420, totalRows * rowHeight + 96);
  return {
    positions, visible, edges, rootIDs: roots.map((root) => root.id),
    center: { x: centerX - 70, y: Math.max(24, (height - 48) / 2) }, width, height,
  };
}

export function themeEvidence(project: AnalysisProject, themeID: string): ThemeEvidenceItem[] {
  return project.interviews.flatMap((interview) => interview.codingUnits.flatMap((unit) => {
    const matchingIDs = unit.themeIDs.filter((id) => isThemeDescendant(project, id, themeID));
    if (!matchingIDs.length) return [];
    const segments = interview.segments.filter((segment) => unit.segmentIDs.includes(segment.id)).sort((a, b) => a.order - b.order);
    return [{
      interviewID: interview.id, unitID: unit.id, participant: interview.participant, interview: interview.name,
      time: segments.length ? `${segments[0].start || '—'}–${segments.at(-1)?.end || '—'}` : '—',
      text: selectedText(interview, unit.segmentIDs), memo: unit.memo,
      assignedPaths: matchingIDs.map((id) => themePathName(project, id)).sort((a, b) => a.localeCompare(b, 'tr')),
    }];
  }));
}
