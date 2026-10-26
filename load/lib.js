// Shared helpers for the k6 scripts.
import http from 'k6/http';

// The lab exposes every site on 127.0.0.1 (port HTTP_PORT, default 80) with a different host name.
export const hosts = {
  'app.localhost': '127.0.0.1',
  'legacy.localhost': '127.0.0.1',
};

export function baseUrl(target) {
  if (__ENV.BASE_URL) return __ENV.BASE_URL;
  const port = __ENV.HTTP_PORT && __ENV.HTTP_PORT !== '80' ? `:${__ENV.HTTP_PORT}` : '';
  return target === 'legacy' ? `http://legacy.localhost${port}` : `http://app.localhost${port}`;
}

export function uuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}

export function hotDate(base) {
  const r = http.get(`${base}/api/info`, { tags: { name: 'info' }, timeout: '10s' });
  if (r.status === 200) {
    try { return r.json('hot_date'); } catch (e) { /* fall through */ }
  }
  const d = new Date(Date.now() + 7 * 3600 * 1000 + 3 * 86400 * 1000);
  return d.toISOString().slice(0, 10);
}

export function dayOffset(days) {
  const d = new Date(Date.now() + 7 * 3600 * 1000 + days * 86400 * 1000);
  return d.toISOString().slice(0, 10);
}

export const routes = [
  ['JKT', 'BDG'], ['BDG', 'JKT'], ['JKT', 'JOG'], ['JOG', 'JKT'], ['JKT', 'SUB'], ['SUB', 'JKT'],
  ['JKT', 'SMG'], ['BDG', 'JOG'], ['JOG', 'SUB'], ['SUB', 'MLG'], ['JKT', 'CBN'], ['JOG', 'SOC'],
];

export const trainsByRoute = {
  'JKT-BDG': ['RN101', 'RN105'], 'BDG-JKT': ['RN102', 'RN106'], 'JKT-JOG': ['RN11', 'RN15'],
  'JOG-JKT': ['RN8', 'RN12', 'RN16'], 'JKT-SUB': ['RN21', 'RN23'], 'SUB-JKT': ['RN22', 'RN24'],
  'JKT-SMG': ['RN31'], 'BDG-JOG': ['RN41'], 'JOG-SUB': ['RN51'], 'SUB-MLG': ['RN61'],
  'JKT-CBN': ['RN71'], 'JOG-SOC': ['RN91'],
};
