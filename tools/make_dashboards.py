#!/usr/bin/env python3
"""Generate the RelNusa Grafana dashboards as Kubernetes ConfigMaps.

Run:  python3 tools/make_dashboards.py   (writes k8s/dashboards/relnusa-dashboards.yaml)

The Grafana sidecar in kube-prometheus-stack picks up ConfigMaps labelled
grafana_dashboard=1 and files them in the folder named by grafana_folder.
"""
import json
import pathlib

DS = {"type": "prometheus", "uid": "prometheus"}
LEGACY = 'router=~"legacy-legacy-.*"'
MODERN = 'router=~"modern-app-.*"'
COL_LEGACY = "#C2410C"
COL_MODERN = "#0E7C66"
OUT = pathlib.Path(__file__).resolve().parent.parent / "k8s" / "dashboards" / "relnusa-dashboards.yaml"


class Layout:
    """Places panels on Grafana's 24-column grid, left to right, top to bottom."""

    def __init__(self):
        self.x = 0
        self.y = 0
        self.row_h = 0
        self.next_id = 1

    def pos(self, w, h):
        if self.x + w > 24:
            self.newline()
        p = {"x": self.x, "y": self.y, "w": w, "h": h}
        self.x += w
        self.row_h = max(self.row_h, h)
        return p

    def newline(self):
        if self.x:
            self.y += self.row_h
        self.x = 0
        self.row_h = 0

    def pid(self):
        self.next_id += 1
        return self.next_id


def target(expr, legend="", ref="A", instant=False, fmt=None):
    t = {"refId": ref, "expr": expr, "legendFormat": legend, "datasource": DS, "range": not instant, "instant": instant}
    if fmt:
        t["format"] = fmt
    return t


def thresholds(*steps):
    out = [{"color": steps[0], "value": None}]
    for i in range(1, len(steps), 2):
        out.append({"value": steps[i], "color": steps[i + 1]})
    return {"mode": "absolute", "steps": out}


def color_overrides(pairs):
    return [{"matcher": {"id": "byName", "options": name},
             "properties": [{"id": "color", "value": {"mode": "fixed", "fixedColor": color}}]} for name, color in pairs]


def timeseries(lay, title, targets, w=12, h=8, unit="short", decimals=None, colors=(), desc="", stack=False,
               minv=None, maxv=None, thresh_lines=None, fill=8, softmax=None):
    custom = {"lineWidth": 2, "fillOpacity": fill, "showPoints": "never", "spanNulls": True, "axisSoftMin": minv}
    if softmax is not None:
        custom["axisSoftMax"] = softmax
    if stack:
        custom["stacking"] = {"mode": "normal", "group": "A"}
    defaults = {"unit": unit, "color": {"mode": "palette-classic"}, "custom": custom}
    if decimals is not None:
        defaults["decimals"] = decimals
    if maxv is not None:
        defaults["max"] = maxv
    if thresh_lines:
        defaults["thresholds"] = thresh_lines
        custom["thresholdsStyle"] = {"mode": "line+area"}
    return {
        "id": lay.pid(), "type": "timeseries", "title": title, "description": desc, "gridPos": lay.pos(w, h),
        "datasource": DS, "targets": targets,
        "fieldConfig": {"defaults": defaults, "overrides": color_overrides(colors)},
        "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": True},
                    "tooltip": {"mode": "multi", "sort": "none"}},
    }


def stat(lay, title, expr, w=6, h=5, unit="short", decimals=None, thr=None, mappings=None, desc="",
         graph=True, color_mode="background", legend=""):
    defaults = {"unit": unit, "thresholds": thr or thresholds("blue"), "mappings": mappings or [],
                "color": {"mode": "thresholds"}}
    if decimals is not None:
        defaults["decimals"] = decimals
    return {
        "id": lay.pid(), "type": "stat", "title": title, "description": desc, "gridPos": lay.pos(w, h),
        "datasource": DS, "targets": [target(expr, legend)],
        "fieldConfig": {"defaults": defaults, "overrides": []},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "colorMode": color_mode, "graphMode": "area" if graph else "none", "textMode": "auto",
                    "justifyMode": "center", "orientation": "auto", "wideLayout": True},
    }


def gauge(lay, title, expr, w=6, h=6, unit="percent", thr=None, desc="", minv=0, maxv=100, mappings=None):
    return {
        "id": lay.pid(), "type": "gauge", "title": title, "description": desc, "gridPos": lay.pos(w, h),
        "datasource": DS, "targets": [target(expr)],
        "fieldConfig": {"defaults": {"unit": unit, "min": minv, "max": maxv, "decimals": 1, "mappings": mappings or [],
                                     "thresholds": thr or thresholds("red", 25, "orange", 50, "green"),
                                     "color": {"mode": "thresholds"}}, "overrides": []},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "showThresholdMarkers": True, "showThresholdLabels": False},
    }


def state_timeline(lay, title, expr, legend, mappings, w=12, h=7, desc=""):
    return {
        "id": lay.pid(), "type": "state-timeline", "title": title, "description": desc, "gridPos": lay.pos(w, h),
        "datasource": DS, "targets": [target(expr, legend)],
        # Fixed colour on purpose: in Grafana 13 a thresholds colour scheme overrides
        # the value mappings in a state timeline, so states would not show.
        "fieldConfig": {"defaults": {"mappings": mappings, "color": {"mode": "fixed", "fixedColor": "#8E8E8E"},
                                     "custom": {"fillOpacity": 85, "lineWidth": 0}},
                        "overrides": []},
        "options": {"showValue": "auto", "mergeValues": True, "alignValue": "center", "rowHeight": 0.85,
                    "legend": {"showLegend": False}},
    }


def table(lay, title, expr, w=24, h=6, desc="", rename=None, hide=("Time", "Value", "__name__")):
    excl = {k: True for k in hide}
    return {
        "id": lay.pid(), "type": "table", "title": title, "description": desc, "gridPos": lay.pos(w, h),
        "datasource": DS, "targets": [target(expr, instant=True, fmt="table")],
        "transformations": [{"id": "organize", "options": {"excludeByName": excl, "renameByName": rename or {}}}],
        "fieldConfig": {"defaults": {}, "overrides": []},
        "options": {"showHeader": True, "cellHeight": "sm"},
    }


def text(lay, title, content, w=24, h=6):
    return {"id": lay.pid(), "type": "text", "title": title, "gridPos": lay.pos(w, h),
            "options": {"mode": "markdown", "content": content}}


def row(lay, title, repeat=None):
    lay.newline()
    p = {"id": lay.pid(), "type": "row", "title": title, "collapsed": False, "panels": [],
         "gridPos": {"x": 0, "y": lay.y, "w": 24, "h": 1}}
    if repeat:
        p["repeat"] = repeat
    lay.y += 1
    return p


def budget_gone():
    """Shows 'Exhausted' instead of a large negative percentage once the budget is used up."""
    return [{"type": "range", "options": {"from": -1e15, "to": 0, "result": {"text": "Exhausted", "color": "red", "index": 0}}}]


def mapping(values):
    """values: list of (value, text, color)."""
    return [{"type": "value", "options": {str(v): {"text": t, "color": c, "index": i}}} for i, (v, t, c) in enumerate(values)]


def dashboard(uid, title, panels, variables=None, refresh="5s", time_from="now-15m", tags=("relnusa",)):
    return {
        "uid": uid, "title": title, "tags": list(tags), "timezone": "browser", "editable": True,
        "graphTooltip": 1, "refresh": refresh, "schemaVersion": 39, "version": 1,
        "time": {"from": time_from, "to": "now"},
        "timepicker": {"refresh_intervals": ["5s", "10s", "30s", "1m", "5m"]},
        "templating": {"list": variables or []}, "annotations": {"list": []}, "panels": panels,
        "links": [
            {"title": "RelNusa dashboards", "type": "dashboards", "tags": ["relnusa"], "asDropdown": True, "includeVars": False},
        ],
    }


def ok_ratio(sel, window):
    return (f'100 * (1 - ((sum(rate(traefik_router_requests_total{{{sel},code=~"5.."}}[{window}])) or vector(0))'
            f' / sum(rate(traefik_router_requests_total{{{sel}}}[{window}]))))')


def p95(sel, window):
    return f'histogram_quantile(0.95, sum by (le) (rate(traefik_router_request_duration_seconds_bucket{{{sel}}}[{window}])))'


PCT_THR = thresholds("red", 99, "orange", 99.9, "green")
LAT_THR = thresholds("green", 0.5, "orange", 2, "red")


# ------------------------------------------------------------------ 00 home
def d00():
    lay = Layout()
    p = []
    p.append(text(lay, "RelNusa availability lab", """
**A fictional train-ticket booking application** in two architectures, for the session *Achieving 99.9% Availability and Beyond*.

| Open | Address |
|---|---|
| Legacy app (single server) | [legacy.__LAB_DOMAIN____URL_PORT__](http://legacy.__LAB_DOMAIN____URL_PORT__) |
| Modern app | [app.__LAB_DOMAIN____URL_PORT__](http://app.__LAB_DOMAIN____URL_PORT__) |
| Traces (Jaeger) | [jaeger.__LAB_DOMAIN____URL_PORT__](http://jaeger.__LAB_DOMAIN____URL_PORT__) |
| Failure experiments (Chaos Mesh) | [chaos.__LAB_DOMAIN____URL_PORT__](http://chaos.__LAB_DOMAIN____URL_PORT__) |
| Progressive delivery (Argo Rollouts) | [rollouts.__LAB_DOMAIN____URL_PORT__](http://rollouts.__LAB_DOMAIN____URL_PORT__/rollouts/modern) |

**Dashboards:** [1 · Before vs after](/d/relnusa-1) · [2 · SLOs and error budgets](/d/relnusa-2) · [3 · Inside the modern architecture](/d/relnusa-3)
""", w=14, h=9))
    p.append(stat(lay, "Kubernetes nodes ready", 'sum(kube_node_status_condition{condition="Ready",status="true"})',
                  w=5, h=9, thr=thresholds("red", 3, "green"), graph=False,
                  desc="The lab uses 3 nodes in 3 zones. During the node-failure demo this drops to 2."))
    p.append(stat(lay, "SLO alerts firing", 'count(ALERTS{alertstate="firing",sloth_slo!=""}) or vector(0)',
                  w=5, h=9, thr=thresholds("green", 1, "red"), graph=False))
    lay.newline()
    p.append(stat(lay, "Legacy · success rate (1 min)", ok_ratio(LEGACY, "1m"), w=6, unit="percent",
                  decimals=2, thr=PCT_THR))
    p.append(stat(lay, "Modern · success rate (1 min)", ok_ratio(MODERN, "1m"), w=6, unit="percent",
                  decimals=2, thr=PCT_THR))
    p.append(stat(lay, "Legacy · 30-day budget left",
                  '100 * slo:period_error_budget_remaining:ratio{sloth_service="relnusa-legacy",sloth_slo="availability"}',
                  w=6, unit="percent", decimals=1, thr=thresholds("red", 25, "orange", 50, "green"), mappings=budget_gone()))
    p.append(stat(lay, "Modern · 30-day budget left",
                  '100 * slo:period_error_budget_remaining:ratio{sloth_service="relnusa-modern",sloth_slo="availability"}',
                  w=6, unit="percent", decimals=1, thr=thresholds("red", 25, "orange", 50, "green"), mappings=budget_gone()))
    return dashboard("relnusa-0", "RelNusa · Overview", p, refresh="10s")


# ------------------------------------------------------------------ 01 before vs after
def d01():
    lay = Layout()
    p = []
    p.append(row(lay, "What passengers experience at the front door (measured at Traefik)"))
    p.append(stat(lay, "Legacy app · successful requests", ok_ratio(LEGACY, "1m"), unit="percent", decimals=2, thr=PCT_THR,
                  desc="Percentage of requests without a server error (5xx, including 504 timeouts) over the last minute."))
    p.append(stat(lay, "Legacy app · p95 response time", p95(LEGACY, "1m"), unit="s", decimals=2, thr=LAT_THR,
                  desc="95% of requests are faster than this."))
    p.append(stat(lay, "Modern app · successful requests", ok_ratio(MODERN, "1m"), unit="percent", decimals=2, thr=PCT_THR))
    p.append(stat(lay, "Modern app · p95 response time", p95(MODERN, "1m"), unit="s", decimals=2, thr=LAT_THR))
    colors = [("Legacy app", COL_LEGACY), ("Modern app", COL_MODERN)]
    p.append(timeseries(lay, "Percentage of successful requests", [
        target(ok_ratio(LEGACY, "30s"), "Legacy app", "A"),
        target(ok_ratio(MODERN, "30s"), "Modern app", "B")], unit="percent", decimals=1, colors=colors, maxv=100))
    p.append(timeseries(lay, "p95 response time (seconds)", [
        target(p95(LEGACY, "30s"), "Legacy app", "A"),
        target(p95(MODERN, "30s"), "Modern app", "B")], unit="s", decimals=2, colors=colors))
    p.append(timeseries(lay, "Server errors per second (5xx, including 504 timeouts)", [
        target(f'sum(rate(traefik_router_requests_total{{{LEGACY},code=~"5.."}}[30s])) or vector(0)', "Legacy app", "A"),
        target(f'sum(rate(traefik_router_requests_total{{{MODERN},code=~"5.."}}[30s])) or vector(0)', "Modern app", "B")],
        unit="reqps", decimals=1, colors=colors))
    p.append(timeseries(lay, "Requests per second", [
        target(f'sum(rate(traefik_router_requests_total{{{LEGACY}}}[30s]))', "Legacy app", "A"),
        target(f'sum(rate(traefik_router_requests_total{{{MODERN}}}[30s]))', "Modern app", "B")],
        unit="reqps", decimals=0, colors=colors))
    p.append(row(lay, "Bookings"))
    p.append(timeseries(lay, "Seats booked per second", [
        target('sum(rate(http_requests_total{namespace="legacy",route="/api/bookings",code="201"}[30s])) or vector(0)', "Legacy app", "A"),
        target('sum(rate(booking_outcomes_total{namespace="modern",outcome="held"}[30s])) or vector(0)', "Modern app", "B")],
        unit="short", decimals=1, colors=colors,
        desc="Legacy app: paid bookings. Modern app: seats locked; the payment follows from the queue."))
    p.append(timeseries(lay, "Virtual waiting room (modern app)", [
        target('sum by (outcome) (rate(waiting_room_requests_total{namespace="modern"}[30s]))', "{{outcome}}")],
        unit="reqps", decimals=0, colors=[("admitted", COL_MODERN), ("queued", "#D97706")],
        desc="admitted = passed on to booking. queued = asked to wait and retry automatically; not an error."))
    p.append(timeseries(lay, "What passengers see (k6): successful bookings per second", [
        target('sum by (target) (rate(k6_booking_ok_total[30s]))', "succeeded · {{target}}")],
        unit="short", decimals=1, colors=[("succeeded · legacy", COL_LEGACY), ("succeeded · modern", COL_MODERN)],
        desc="Measured from the user's side by k6, not by the server."))
    p.append(timeseries(lay, "What passengers see (k6): failed bookings per second", [
        target('sum by (target) (rate(k6_booking_failed_total[30s]))', "failed · {{target}}")],
        unit="short", decimals=1, colors=[("failed · legacy", COL_LEGACY), ("failed · modern", COL_MODERN)]))
    return dashboard("relnusa-1", "RelNusa · 1 · Before vs after", p)


# ------------------------------------------------------------------ 02 SLO
def d02():
    lay = Layout()
    sel = 'sloth_service="$service",sloth_slo="$slo"'
    variables = [
        {"name": "service", "label": "Service", "type": "custom", "query": "relnusa-modern,relnusa-legacy",
         "current": {"text": "relnusa-modern", "value": "relnusa-modern"},
         "options": [{"text": "relnusa-modern", "value": "relnusa-modern", "selected": True},
                     {"text": "relnusa-legacy", "value": "relnusa-legacy", "selected": False}]},
        # An instant query lists only the SLOs that exist now. label_values would also
        # list SLOs that were renamed or removed within the dashboard's time range.
        {"name": "slo", "label": "SLO", "type": "query", "datasource": DS,
         "query": {"query": 'query_result(slo:objective:ratio{sloth_service="$service"})', "refId": "slo"},
         "definition": 'query_result(slo:objective:ratio{sloth_service="$service"})',
         "regex": '/sloth_slo="([^"]+)"/',
         "multi": True, "includeAll": True, "current": {"text": ["All"], "value": ["$__all"]}, "refresh": 2, "sort": 1},
    ]
    p = []
    p.append(row(lay, "SLO alerts currently firing"))
    p.append(table(lay, "Active alerts (sent to Telegram if configured)",
                   'ALERTS{alertstate="firing",sloth_slo!=""}', h=5,
                   hide=("Time", "Value", "__name__", "alertstate", "sloth_id", "sloth_mode", "team", "architecture"),
                   rename={"alertname": "Alert", "sloth_service": "Service", "sloth_slo": "SLO", "severity": "Severity",
                           "category": "Category", "sloth_severity": "Burn-rate tier"}))
    p.append(row(lay, "SLO $slo", repeat="slo"))
    p.append(stat(lay, "Target", f'100 * slo:objective:ratio{{{sel}}}', w=4, unit="percent", decimals=2,
                  thr=thresholds("blue"), graph=False, color_mode="value"))
    p.append(stat(lay, "SLI, last 5 minutes", f'100 * (1 - slo:sli_error:ratio_rate5m{{{sel}}})', w=5, unit="percent",
                  decimals=3, thr=PCT_THR))
    p.append(gauge(lay, "Budget left (30 days)", f'100 * slo:period_error_budget_remaining:ratio{{{sel}}}', w=5, h=5,
                   mappings=budget_gone()))
    p.append(stat(lay, "Current burn rate", f'slo:current_burn_rate:ratio{{{sel}}}', w=4, decimals=1,
                  thr=thresholds("green", 1, "orange", 6, "red"),
                  desc="1 = the error budget runs out exactly at the end of the 30-day period. 14.4 = it runs out in about 2 days."))
    p.append(timeseries(lay, "Burn rate: 5 minutes and 1 hour", [
        target(f'slo:sli_error:ratio_rate5m{{{sel}}} / ignoring (sloth_window) slo:error_budget:ratio{{{sel}}}', "5 minutes", "A"),
        target(f'slo:sli_error:ratio_rate1h{{{sel}}} / ignoring (sloth_window) slo:error_budget:ratio{{{sel}}}', "1 hour", "B")],
        w=6, h=5, decimals=1, thresh_lines=thresholds("transparent", 6, "rgba(217,119,6,0.15)", 14.4, "rgba(194,65,12,0.18)"),
        desc="The page alert fires when the 1-hour and 5-minute burn rates are both above 14.4."))
    lay.newline()
    return dashboard("relnusa-2", "RelNusa · 2 · SLOs and error budgets", p, variables=variables, refresh="10s",
                     time_from="now-1h")


# ------------------------------------------------------------------ 03 inside modern
def d03():
    lay = Layout()
    p = []
    p.append(row(lay, "Nodes and pods"))
    p.append(state_timeline(lay, "Node status", 'max by (node) (kube_node_status_condition{condition="Ready",status="true"})',
                            "{{node}}", mapping([(1, "Ready", "green"), (0, "Down", "red")]), w=12, h=7))
    p.append(timeseries(lay, "Modern app pods serving", [
        target('sum by (app) (up{namespace="modern",job="observability/relnusa"})', "{{app}}")],
        w=6, h=7, decimals=0, stack=True, fill=60))
    p.append(timeseries(lay, "Search replicas (autoscaling)", [
        target('max(kube_horizontalpodautoscaler_status_current_replicas{namespace="modern",horizontalpodautoscaler="search"})', "running", "A"),
        target('max(kube_horizontalpodautoscaler_status_desired_replicas{namespace="modern",horizontalpodautoscaler="search"})', "desired", "B")],
        w=6, h=7, decimals=0))
    p.append(row(lay, "Payments and the bank"))
    p.append(stat(lay, "Circuit breaker to the bank", 'max(payment_circuit_state{namespace="modern"})', w=6, h=7, graph=False,
                  mappings=mapping([(0, "Closed (normal)", "green"), (1, "Half-open (testing)", "orange"),
                                    (2, "Open (bank is being protected)", "red")]),
                  thr=thresholds("green", 1, "orange", 2, "red")))
    p.append(timeseries(lay, "Payment attempts per second by outcome", [
        target('sum by (outcome) (rate(payment_attempts_total{namespace="modern"}[30s]))', "{{outcome}}")],
        w=9, h=7, decimals=1, stack=True, fill=50,
        colors=[("success", COL_MODERN), ("timeout", "#D97706"), ("failure", "#B42318"), ("circuit_open", "#7C3AED"),
                ("error", "#6B7280")]))
    p.append(timeseries(lay, "Payments waiting in the queue", [
        target('max(payment_queue_pending{namespace="modern"})', "pending")], w=9, h=7, decimals=0))
    p.append(stat(lay, "Double charges prevented", 'sum(bank_requests_total{namespace="bank",outcome="duplicate"}) or vector(0)',
                  w=6, h=5, graph=False, thr=thresholds("blue"), color_mode="value",
                  desc="Repeated requests with the same idempotency key. The bank returns the earlier result instead of charging again."))
    p.append(stat(lay, "Simulated bank mode (base latency)", 'max(bank_configured_latency_ms{namespace="bank"})', w=6, h=5,
                  unit="ms", graph=False, thr=thresholds("green", 1000, "red"), color_mode="value"))
    p.append(timeseries(lay, "Booking p95 response time (seconds)", [
        target('histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="modern",service="booking",route="/api/bookings"}[1m])))', "booking"),
        target('histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="legacy",route="/api/bookings"}[1m])))', "monolith (comparison)", "B")],
        w=12, h=5, unit="s", decimals=2, colors=[("booking", COL_MODERN), ("monolith (comparison)", COL_LEGACY)]))
    p.append(row(lay, "PostgreSQL database (CloudNativePG)"))
    p.append(state_timeline(lay, "Database instance roles", 'max by (pod) (1 - cnpg_pg_replication_in_recovery{namespace="modern"})',
                            "{{pod}}", mapping([(1, "Primary", "blue"), (0, "Replica", "green")]), w=12, h=6,
                            desc="When the primary fails, one of the replicas is promoted to primary."))
    p.append(timeseries(lay, "Replication lag (seconds)", [
        target('max by (pod) (cnpg_pg_replication_lag{namespace="modern"})', "{{pod}}")], w=6, h=6, unit="s", decimals=2))
    p.append(timeseries(lay, "Active database connections", [
        target('sum by (pod) (cnpg_backends_total{namespace="modern"})', "{{pod}}")], w=6, h=6, decimals=0))
    p.append(row(lay, "Search cache and booking releases"))
    p.append(timeseries(lay, "Search answers by source", [
        target('sum by (source) (rate(search_cache_requests_total{namespace="modern"}[30s]))', "{{source}}")],
        w=8, h=7, unit="reqps", decimals=0, stack=True, fill=50,
        colors=[("cache", COL_MODERN), ("database", "#2563EB"), ("stale-cache", "#D97706")]))
    p.append(timeseries(lay, "Booking errors by version", [
        # The "or ... * 0" part draws a zero line per version while there are no errors yet.
        target('sum by (version) ('
               '(sum by (pod) (rate(http_requests_total{namespace="modern",service="booking",route="/api/bookings",code=~"5.."}[30s])) '
               'or sum by (pod) (rate(http_requests_total{namespace="modern",service="booking",route="/api/bookings"}[30s])) * 0) '
               '* on (pod) group_left (version) max by (pod, version) (relnusa_build_info{namespace="modern",service="booking"}))', "{{version}}")],
        w=8, h=7, unit="reqps", decimals=2, minv=0, softmax=1))
    p.append(timeseries(lay, "Booking pods by version", [
        target('count by (version) (relnusa_build_info{namespace="modern",service="booking"})', "{{version}}")],
        w=8, h=7, decimals=0, stack=True, fill=60))
    return dashboard("relnusa-3", "RelNusa · 3 · Inside the modern architecture", p)


def configmap(name, filename, dash):
    body = json.dumps(dash, ensure_ascii=False, indent=1)
    indented = "\n".join("    " + line for line in body.splitlines())
    return (f"apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: {name}\n  namespace: observability\n"
            f"  labels:\n    grafana_dashboard: \"1\"\n  annotations:\n    grafana_folder: RelNusa\n"
            f"data:\n  {filename}: |-\n{indented}\n")


def main():
    docs = [
        configmap("relnusa-dashboard-00", "relnusa-00-overview.json", d00()),
        configmap("relnusa-dashboard-01", "relnusa-01-before-after.json", d01()),
        configmap("relnusa-dashboard-02", "relnusa-02-slo.json", d02()),
        configmap("relnusa-dashboard-03", "relnusa-03-modern.json", d03()),
    ]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("# Generated by tools/make_dashboards.py. Edit that file, not this one.\n" + "---\n".join(docs))
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
