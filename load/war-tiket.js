// "War tiket": thousands of people try to book the same popular train the
// moment sales open. Run it against the legacy site, then the modern one.
//
//   TARGET=legacy|modern  PEAK_RATE=150 (new buyers per second)  HOLD=90s
import http from 'k6/http';
import { sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import { hosts, baseUrl, uuid, hotDate } from './lib.js';

const TARGET = __ENV.TARGET || 'modern';
const BASE = baseUrl(TARGET);
const PEAK = Number(__ENV.PEAK_RATE || 150);
const HOLD = __ENV.HOLD || '90s';

export const options = {
  hosts,
  systemTags: ['status', 'method', 'name', 'scenario', 'expected_response'],
  tags: { target: TARGET, test: 'war-tiket' },
  scenarios: {
    pembeli: {
      executor: 'ramping-arrival-rate',
      startRate: 5,
      timeUnit: '1s',
      preAllocatedVUs: 200,
      maxVUs: Number(__ENV.MAX_VUS || 2000),
      stages: [
        { target: 10, duration: '10s' },
        { target: PEAK, duration: '10s' },
        { target: PEAK, duration: HOLD },
        { target: 0, duration: '10s' },
      ],
      gracefulStop: '30s',
    },
  },
  summaryTrendStats: ['avg', 'p(50)', 'p(95)', 'p(99)', 'max'],
};

const booked = new Counter('booking_ok');
const queued = new Counter('booking_queued');
const soldOut = new Counter('booking_soldout');
const failed = new Counter('booking_failed');
const timeToSeat = new Trend('time_to_seat', true);

export function setup() {
  return { date: hotDate(BASE) };
}

const expected = http.expectedStatuses(200, 201, 202, 409);

export default function (data) {
  const started = Date.now();
  const s = http.get(`${BASE}/api/search?from=JKT&to=JOG&date=${data.date}`, {
    tags: { name: 'search' }, timeout: '20s',
  });
  if (s.status !== 200) {
    failed.add(1, { step: 'search' });
    return;
  }
  const key = uuid();
  const body = JSON.stringify({ train_id: 'RN7', date: data.date, passenger: `Penumpang ${__VU}-${__ITER}` });
  const params = {
    headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key },
    tags: { name: 'booking' }, timeout: '20s', responseCallback: expected,
  };
  for (let attempt = 0; attempt < 20; attempt++) {
    const r = http.post(`${BASE}/api/bookings`, body, params);
    let status = '';
    try { status = r.json('status') || ''; } catch (e) { /* not JSON */ }
    if (r.status === 200 && status === 'QUEUED') {
      queued.add(1);
      let wait = 2000;
      try { wait = r.json('retry_after_ms') || 2000; } catch (e) { /* default */ }
      sleep(wait / 1000);
      continue;
    }
    if (r.status === 200 || r.status === 201 || r.status === 202) {
      booked.add(1);
      timeToSeat.add(Date.now() - started);
      return;
    }
    if (r.status === 409) {
      soldOut.add(1);
      return;
    }
    failed.add(1, { step: 'booking' });
    return;
  }
  failed.add(1, { step: 'gave-up-in-queue' });
}
