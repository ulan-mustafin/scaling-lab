import http from 'k6/http';
import { check } from 'k6';

const baseUrl = __ENV.BASE_URL || 'http://nginx';
const iterations = __ENV.ITERATIONS || '50000';

export const options = {
  vus: Number(__ENV.VUS || 25),
  duration: __ENV.DURATION || '60s',
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
  thresholds: { http_req_failed: ['rate<0.05'] },
};

export default function () {
  const response = http.get(`${baseUrl}/work?iterations=${iterations}`);
  check(response, { 'status is 200': (r) => r.status === 200 });
}
