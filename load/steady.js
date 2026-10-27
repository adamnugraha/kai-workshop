// Background traffic for both sites so dashboards always have data:
// mostly searches, some bookings on ordinary trains, some status checks.
//
//   RATE=4 (journeys per second per site)  DURATION=720h
import http from 'k6/http';
import { sleep } from 'k6';
import { hosts, baseUrl, uuid, dayOffset, routes, trainsByRoute } from './lib.js';

const RATE = Number(__ENV.RATE || 4);
const DURATION = __ENV.DURATION || '720h';
const SITES = (__ENV.SITES || 'legacy,modern').split(',');

const scenarios = {};
for (const site of SITES) {
  scenarios[site] = {
    executor: 'constant-arrival-rate',
    rate: RATE,
    timeUnit: '1s',
    duration: DURATION,
    preAllocatedVUs: 20,
    maxVUs: 400,
    exec: 'journey',
    env: { SITE: site },
    tags: { target: site },
  };
}

export const options = {
  hosts,
  systemTags: ['status', 'method', 'name', 'scenario', 'expected_response'],
  tags: { test: 'steady' },
  scenarios,
};

const expected = http.expectedStatuses(200, 201, 202, 409);

export function journey() {
  const base = baseUrl(__ENV.SITE);
  const [from, to] = routes[Math.floor(Math.random() * routes.length)];
  const date = dayOffset(1 + Math.floor(Math.random() * 7));
  const s = http.get(`${base}/api/search?from=${from}&to=${to}&date=${date}`, { tags: { name: 'search' }, timeout: '20s' });
  if (s.status !== 200 || Math.random() > 0.25) return;
  const options = trainsByRoute[`${from}-${to}`];
  const train = options[Math.floor(Math.random() * options.length)];
  const r = http.post(`${base}/api/bookings`,
    JSON.stringify({ train_id: train, date, passenger: 'Daily Passenger' }),
    { headers: { 'Content-Type': 'application/json', 'Idempotency-Key': uuid() }, tags: { name: 'booking' }, timeout: '20s', responseCallback: expected });
  if (r.status !== 200 && r.status !== 201 && r.status !== 202) return;
  let id = '';
  try { id = r.json('booking.id'); } catch (e) { return; }
  if (!id) return;
  sleep(2);
  http.get(`${base}/api/bookings/${id}`, { tags: { name: 'booking-status' }, timeout: '20s' });
}
