import { z } from 'zod';

const uuid = z.string().uuid();
const isoDate = z.string().datetime({ offset: true });

export const transcriptSegmentSchema = z.object({
  id: uuid,
  order: z.number().int().positive(),
  part: z.number().int().nullable().optional(),
  speaker: z.string(),
  start: z.string(),
  end: z.string(),
  text: z.string(),
});

export const participantDetailsSchema = z.object({
  gender: z.string().default(''),
  age: z.string().default(''),
  education: z.string().default(''),
  occupation: z.string().default(''),
  employmentStatus: z.string().default(''),
  sector: z.string().default(''),
  experienceYears: z.string().default(''),
  maritalStatus: z.string().default(''),
  location: z.string().default(''),
  notes: z.string().default(''),
});

export const codingUnitSchema = z.object({
  id: uuid,
  segmentIDs: z.array(uuid),
  themeIDs: z.array(uuid),
  memo: z.string(),
  createdAt: isoDate,
});

export const interviewSchema = z.object({
  id: uuid,
  name: z.string().min(1),
  participant: z.string().min(1),
  participantDetails: participantDetailsSchema.nullable().optional(),
  importedAt: isoDate,
  segments: z.array(transcriptSegmentSchema),
  codingUnits: z.array(codingUnitSchema).default([]),
});

export const themeNodeSchema = z.object({
  id: uuid,
  name: z.string().min(1),
  parentID: uuid.nullable().optional(),
  colorIndex: z.number().int().nonnegative(),
  note: z.string().nullable().optional(),
});

export const analysisProjectSchema = z.object({
  name: z.string().min(1),
  interviews: z.array(interviewSchema),
  themes: z.array(themeNodeSchema),
  updatedAt: isoDate,
});

export type TranscriptSegment = z.infer<typeof transcriptSegmentSchema>;
export type ParticipantDetails = z.infer<typeof participantDetailsSchema>;
export type CodingUnit = z.infer<typeof codingUnitSchema>;
export type Interview = z.infer<typeof interviewSchema>;
export type ThemeNode = z.infer<typeof themeNodeSchema>;
export type AnalysisProject = z.infer<typeof analysisProjectSchema>;

export interface ProjectRecord {
  id: string;
  project: AnalysisProject;
}

export interface ThemeUsage {
  theme: ThemeNode;
  codingCount: number;
  participantCount: number;
}

export const emptyDetails = (): ParticipantDetails => ({
  gender: '', age: '', education: '', occupation: '', employmentStatus: '',
  sector: '', experienceYears: '', maritalStatus: '', location: '', notes: '',
});

export function createProject(name: string): AnalysisProject {
  return { name: name.trim(), interviews: [], themes: [], updatedAt: new Date().toISOString() };
}

export function touch(project: AnalysisProject): AnalysisProject {
  return { ...project, updatedAt: new Date().toISOString() };
}

export function childrenOf(project: AnalysisProject, parentID: string | null): ThemeNode[] {
  return project.themes
    .filter((theme) => (theme.parentID ?? null) === parentID)
    .sort((a, b) => a.name.localeCompare(b.name, 'tr'));
}

export function themePath(project: AnalysisProject, themeID: string): ThemeNode[] {
  const path: ThemeNode[] = [];
  const visited = new Set<string>();
  let cursor = project.themes.find((theme) => theme.id === themeID);
  while (cursor && !visited.has(cursor.id)) {
    visited.add(cursor.id);
    path.unshift(cursor);
    cursor = cursor.parentID ? project.themes.find((theme) => theme.id === cursor?.parentID) : undefined;
  }
  return path;
}

export function themePathName(project: AnalysisProject, themeID: string): string {
  return themePath(project, themeID).map((theme) => theme.name).join(' › ');
}

export function isThemeDescendant(project: AnalysisProject, themeID: string, ancestorID: string): boolean {
  return themePath(project, themeID).some((theme) => theme.id === ancestorID);
}

export function selectedText(interview: Interview, segmentIDs: string[]): string {
  const selected = new Set(segmentIDs);
  return interview.segments
    .filter((segment) => selected.has(segment.id))
    .sort((a, b) => a.order - b.order)
    .map((segment) => segment.text)
    .join(' ');
}

export function saveCodingUnit(
  interview: Interview,
  segmentIDs: string[],
  themeIDs: string[],
  memo: string,
): Interview {
  const orderedIDs = interview.segments
    .filter((segment) => segmentIDs.includes(segment.id))
    .sort((a, b) => a.order - b.order)
    .map((segment) => segment.id);
  if (!orderedIDs.length || !themeIDs.length) return interview;
  const key = [...orderedIDs].sort().join('|');
  const existingIndex = interview.codingUnits.findIndex(
    (unit) => [...unit.segmentIDs].sort().join('|') === key,
  );
  const codingUnits = [...interview.codingUnits];
  if (existingIndex >= 0) {
    const current = codingUnits[existingIndex];
    codingUnits[existingIndex] = {
      ...current,
      themeIDs: [...new Set([...current.themeIDs, ...themeIDs])],
      memo: memo.trim() || current.memo,
    };
  } else {
    codingUnits.push({
      id: crypto.randomUUID(),
      segmentIDs: orderedIDs,
      themeIDs: [...new Set(themeIDs)],
      memo: memo.trim(),
      createdAt: new Date().toISOString(),
    });
  }
  return { ...interview, codingUnits };
}

export function removeCodingUnit(interview: Interview, unitID: string): Interview {
  return { ...interview, codingUnits: interview.codingUnits.filter((unit) => unit.id !== unitID) };
}

export function themeUsage(project: AnalysisProject): ThemeUsage[] {
  return project.themes.map((theme) => {
    let codingCount = 0;
    let participantCount = 0;
    for (const interview of project.interviews) {
      const matches = interview.codingUnits.filter((unit) =>
        unit.themeIDs.some((id) => isThemeDescendant(project, id, theme.id)),
      );
      codingCount += matches.length;
      if (matches.length) participantCount += 1;
    }
    return { theme, codingCount, participantCount };
  }).sort((a, b) => b.codingCount - a.codingCount || a.theme.name.localeCompare(b.theme.name, 'tr'));
}

export function validateProject(input: unknown): AnalysisProject {
  return analysisProjectSchema.parse(input);
}

export function migrateLegacyPrototype(input: unknown): AnalysisProject | null {
  const legacy = z.object({
    name: z.string().min(1),
    updatedAt: z.union([z.string(), z.number()]).optional(),
    participants: z.array(z.object({
      id: z.string(), name: z.string(), gender: z.string().optional(), age: z.string().optional(),
      education: z.string().optional(), job: z.string().optional(), interview: z.string().optional(),
    })),
  }).safeParse(input);
  if (!legacy.success) return null;
  const legacyUpdatedAt = typeof legacy.data.updatedAt === 'string'
    ? new Date(legacy.data.updatedAt)
    : new Date(legacy.data.updatedAt ?? Date.now());
  return {
    name: legacy.data.name,
    updatedAt: Number.isNaN(legacyUpdatedAt.getTime()) ? new Date().toISOString() : legacyUpdatedAt.toISOString(),
    themes: [],
    interviews: legacy.data.participants.map((participant, index) => ({
      id: z.string().uuid().safeParse(participant.id).success ? participant.id : crypto.randomUUID(),
      name: participant.interview || `${participant.name} Transkripti`,
      participant: participant.name,
      participantDetails: {
        ...emptyDetails(), gender: participant.gender ?? '', age: participant.age ?? '',
        education: participant.education ?? '', occupation: participant.job ?? '',
      },
      importedAt: new Date().toISOString(),
      segments: [], codingUnits: [],
    })),
  };
}
