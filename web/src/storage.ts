import { openDB, type DBSchema, type IDBPDatabase } from 'idb';
import type { AnalysisProject, ProjectRecord } from './domain';
import { validateProject } from './domain';

interface TematikDB extends DBSchema {
  projects: {
    key: string;
    value: ProjectRecord;
    indexes: { 'by-updated': string };
  };
}

const DB_NAME = 'tematik-analiz-web';
const DB_VERSION = 1;

let connection: Promise<IDBPDatabase<TematikDB>> | null = null;

function database(): Promise<IDBPDatabase<TematikDB>> {
  if (!connection) {
    connection = openDB<TematikDB>(DB_NAME, DB_VERSION, {
      upgrade(db) {
        const store = db.createObjectStore('projects', { keyPath: 'id' });
        store.createIndex('by-updated', 'project.updatedAt');
      },
    });
  }
  return connection;
}

export async function listProjects(): Promise<ProjectRecord[]> {
  const db = await database();
  const records = await db.getAll('projects');
  return records
    .map((record) => ({ ...record, project: validateProject(record.project) }))
    .sort((a, b) => b.project.updatedAt.localeCompare(a.project.updatedAt));
}

export async function saveProject(record: ProjectRecord): Promise<void> {
  const project = validateProject(record.project);
  const db = await database();
  const transaction = db.transaction('projects', 'readwrite');
  await transaction.store.put({ id: record.id, project });
  await transaction.done;
}

export async function importProject(project: AnalysisProject): Promise<ProjectRecord> {
  const record = { id: crypto.randomUUID(), project: validateProject(project) };
  await saveProject(record);
  return record;
}

export async function deleteProject(id: string): Promise<void> {
  const db = await database();
  const transaction = db.transaction('projects', 'readwrite');
  await transaction.store.delete(id);
  await transaction.done;
}

export async function projectCount(): Promise<number> {
  return (await database()).count('projects');
}
