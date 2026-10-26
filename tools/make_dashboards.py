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
    """Shows 'Habis' instead of a large negative percentage once the budget is used up."""
    return [{"type": "range", "options": {"from": -1e15, "to": 0, "result": {"text": "Habis", "color": "red", "index": 0}}}]


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
            {"title": "Dasbor RelNusa", "type": "dashboards", "tags": ["relnusa"], "asDropdown": True, "includeVars": False},
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
    p.append(text(lay, "Lab ketersediaan RelNusa", """
**Aplikasi pemesanan tiket kereta fiktif** dalam dua arsitektur, untuk sesi *Mencapai ketersediaan 99,9% ke atas*.

| Buka | Alamat (lewat SSH tunnel) |
|---|---|
| Aplikasi lama (satu server) | [legacy.localhost:8080](http://legacy.localhost:8080) |
| Aplikasi modern | [app.localhost:8080](http://app.localhost:8080) |
| Trace (Jaeger) | [jaeger.localhost:8080](http://jaeger.localhost:8080) |
| Eksperimen kegagalan (Chaos Mesh) | [chaos.localhost:8080](http://chaos.localhost:8080) |
| Rilis bertahap (Argo Rollouts) | [rollouts.localhost:8080](http://rollouts.localhost:8080/rollouts/modern) |

**Dasbor:** [1 · Sebelum vs sesudah](/d/relnusa-1) · [2 · SLO dan error budget](/d/relnusa-2) · [3 · Di dalam arsitektur modern](/d/relnusa-3)
""", w=14, h=9))
    p.append(stat(lay, "Node Kubernetes yang siap", 'sum(kube_node_status_condition{condition="Ready",status="true"})',
                  w=5, h=9, thr=thresholds("red", 3, "green"), graph=False,
                  desc="Lab memakai 3 node di 3 zona. Saat demo node mati, angka ini turun ke 2."))
    p.append(stat(lay, "Alert SLO yang aktif", 'count(ALERTS{alertstate="firing",sloth_slo!=""}) or vector(0)',
                  w=5, h=9, thr=thresholds("green", 1, "red"), graph=False))
    lay.newline()
    p.append(stat(lay, "Aplikasi lama · permintaan berhasil (1 menit)", ok_ratio(LEGACY, "1m"), w=6, unit="percent",
                  decimals=2, thr=PCT_THR))
    p.append(stat(lay, "Aplikasi modern · permintaan berhasil (1 menit)", ok_ratio(MODERN, "1m"), w=6, unit="percent",
                  decimals=2, thr=PCT_THR))
    p.append(stat(lay, "Aplikasi lama · sisa error budget 30 hari",
                  '100 * slo:period_error_budget_remaining:ratio{sloth_service="relnusa-legacy",sloth_slo="ketersediaan"}',
                  w=6, unit="percent", decimals=1, thr=thresholds("red", 25, "orange", 50, "green"), mappings=budget_gone()))
    p.append(stat(lay, "Aplikasi modern · sisa error budget 30 hari",
                  '100 * slo:period_error_budget_remaining:ratio{sloth_service="relnusa-modern",sloth_slo="ketersediaan"}',
                  w=6, unit="percent", decimals=1, thr=thresholds("red", 25, "orange", 50, "green"), mappings=budget_gone()))
    return dashboard("relnusa-0", "RelNusa · Ringkasan", p, refresh="10s")


# ------------------------------------------------------------------ 01 before vs after
def d01():
    lay = Layout()
    p = []
    p.append(row(lay, "Yang dialami penumpang di pintu masuk (diukur di Traefik)"))
    p.append(stat(lay, "Aplikasi lama · permintaan berhasil", ok_ratio(LEGACY, "1m"), unit="percent", decimals=2, thr=PCT_THR,
                  desc="Persentase permintaan tanpa error server (5xx, termasuk 504 timeout) dalam 1 menit terakhir."))
    p.append(stat(lay, "Aplikasi lama · waktu respons p95", p95(LEGACY, "1m"), unit="s", decimals=2, thr=LAT_THR,
                  desc="95% permintaan lebih cepat dari angka ini."))
    p.append(stat(lay, "Aplikasi modern · permintaan berhasil", ok_ratio(MODERN, "1m"), unit="percent", decimals=2, thr=PCT_THR))
    p.append(stat(lay, "Aplikasi modern · waktu respons p95", p95(MODERN, "1m"), unit="s", decimals=2, thr=LAT_THR))
    colors = [("Aplikasi lama", COL_LEGACY), ("Aplikasi modern", COL_MODERN)]
    p.append(timeseries(lay, "Persentase permintaan berhasil", [
        target(ok_ratio(LEGACY, "30s"), "Aplikasi lama", "A"),
        target(ok_ratio(MODERN, "30s"), "Aplikasi modern", "B")], unit="percent", decimals=1, colors=colors, maxv=100))
    p.append(timeseries(lay, "Waktu respons p95 (detik)", [
        target(p95(LEGACY, "30s"), "Aplikasi lama", "A"),
        target(p95(MODERN, "30s"), "Aplikasi modern", "B")], unit="s", decimals=2, colors=colors))
    p.append(timeseries(lay, "Error server per detik (5xx, termasuk 504 timeout)", [
        target(f'sum(rate(traefik_router_requests_total{{{LEGACY},code=~"5.."}}[30s])) or vector(0)', "Aplikasi lama", "A"),
        target(f'sum(rate(traefik_router_requests_total{{{MODERN},code=~"5.."}}[30s])) or vector(0)', "Aplikasi modern", "B")],
        unit="reqps", decimals=1, colors=colors))
    p.append(timeseries(lay, "Permintaan per detik", [
        target(f'sum(rate(traefik_router_requests_total{{{LEGACY}}}[30s]))', "Aplikasi lama", "A"),
        target(f'sum(rate(traefik_router_requests_total{{{MODERN}}}[30s]))', "Aplikasi modern", "B")],
        unit="reqps", decimals=0, colors=colors))
    p.append(row(lay, "Pemesanan"))
    p.append(timeseries(lay, "Kursi berhasil dipesan per detik", [
        target('sum(rate(http_requests_total{namespace="legacy",route="/api/bookings",code="201"}[30s])) or vector(0)', "Aplikasi lama", "A"),
        target('sum(rate(booking_outcomes_total{namespace="modern",outcome="held"}[30s])) or vector(0)', "Aplikasi modern", "B")],
        unit="short", decimals=1, colors=colors,
        desc="Aplikasi lama: pemesanan yang lunas. Aplikasi modern: kursi yang sudah dikunci; pembayaran menyusul dari antrean."))
    p.append(timeseries(lay, "Ruang tunggu virtual (aplikasi modern)", [
        target('sum by (outcome) (rate(waiting_room_requests_total{namespace="modern"}[30s]))', "{{outcome}}")],
        unit="reqps", decimals=0, colors=[("admitted", COL_MODERN), ("queued", "#D97706")],
        desc="admitted = diteruskan ke booking. queued = diminta menunggu dan mencoba lagi otomatis, bukan error."))
    p.append(timeseries(lay, "Yang dirasakan penumpang (k6): pemesanan berhasil per detik", [
        target('sum by (target) (rate(k6_booking_ok_total[30s]))', "berhasil · {{target}}")],
        unit="short", decimals=1, colors=[("berhasil · legacy", COL_LEGACY), ("berhasil · modern", COL_MODERN)],
        desc="Diukur dari sisi pengguna oleh k6, bukan dari server."))
    p.append(timeseries(lay, "Yang dirasakan penumpang (k6): pemesanan gagal per detik", [
        target('sum by (target) (rate(k6_booking_failed_total[30s]))', "gagal · {{target}}")],
        unit="short", decimals=1, colors=[("gagal · legacy", COL_LEGACY), ("gagal · modern", COL_MODERN)]))
    return dashboard("relnusa-1", "RelNusa · 1 · Sebelum vs sesudah", p)


# ------------------------------------------------------------------ 02 SLO
def d02():
    lay = Layout()
    sel = 'sloth_service="$service",sloth_slo="$slo"'
    variables = [
        {"name": "service", "label": "Layanan", "type": "custom", "query": "relnusa-modern,relnusa-legacy",
         "current": {"text": "relnusa-modern", "value": "relnusa-modern"},
         "options": [{"text": "relnusa-modern", "value": "relnusa-modern", "selected": True},
                     {"text": "relnusa-legacy", "value": "relnusa-legacy", "selected": False}]},
        {"name": "slo", "label": "SLO", "type": "query", "datasource": DS,
         "query": {"query": 'label_values(slo:objective:ratio{sloth_service="$service"}, sloth_slo)', "refId": "slo"},
         "definition": 'label_values(slo:objective:ratio{sloth_service="$service"}, sloth_slo)',
         "multi": True, "includeAll": True, "current": {"text": ["All"], "value": ["$__all"]}, "refresh": 2, "sort": 1},
    ]
    p = []
    p.append(row(lay, "Alert SLO yang sedang aktif"))
    p.append(table(lay, "Alert aktif (dikirim ke Telegram bila dikonfigurasi)",
                   'ALERTS{alertstate="firing",sloth_slo!=""}', h=5,
                   hide=("Time", "Value", "__name__", "alertstate", "sloth_id", "sloth_mode", "team", "arsitektur"),
                   rename={"alertname": "Alert", "sloth_service": "Layanan", "sloth_slo": "SLO", "severity": "Tingkat",
                           "category": "Kategori", "sloth_severity": "Jenis burn rate"}))
    p.append(row(lay, "SLO $slo", repeat="slo"))
    p.append(stat(lay, "Target", f'100 * slo:objective:ratio{{{sel}}}', w=4, unit="percent", decimals=2,
                  thr=thresholds("blue"), graph=False, color_mode="value"))
    p.append(stat(lay, "SLI 5 menit terakhir", f'100 * (1 - slo:sli_error:ratio_rate5m{{{sel}}})', w=5, unit="percent",
                  decimals=3, thr=PCT_THR))
    p.append(gauge(lay, "Sisa error budget (30 hari)", f'100 * slo:period_error_budget_remaining:ratio{{{sel}}}', w=5, h=5,
                   mappings=budget_gone()))
    p.append(stat(lay, "Burn rate saat ini", f'slo:current_burn_rate:ratio{{{sel}}}', w=4, decimals=1,
                  thr=thresholds("green", 1, "orange", 6, "red"),
                  desc="1 = error budget habis tepat di akhir periode 30 hari. 14,4 = habis dalam sekitar 2 hari."))
    p.append(timeseries(lay, "Burn rate: 5 menit dan 1 jam", [
        target(f'slo:sli_error:ratio_rate5m{{{sel}}} / ignoring (sloth_window) slo:error_budget:ratio{{{sel}}}', "5 menit", "A"),
        target(f'slo:sli_error:ratio_rate1h{{{sel}}} / ignoring (sloth_window) slo:error_budget:ratio{{{sel}}}', "1 jam", "B")],
        w=6, h=5, decimals=1, thresh_lines=thresholds("transparent", 6, "rgba(217,119,6,0.15)", 14.4, "rgba(194,65,12,0.18)"),
        desc="Alert page menyala bila burn rate 1 jam dan 5 menit sama-sama di atas 14,4."))
    lay.newline()
    return dashboard("relnusa-2", "RelNusa · 2 · SLO dan error budget", p, variables=variables, refresh="10s",
                     time_from="now-1h")


# ------------------------------------------------------------------ 03 inside modern
def d03():
    lay = Layout()
    p = []
    p.append(row(lay, "Node dan pod"))
    p.append(state_timeline(lay, "Status node", 'max by (node) (kube_node_status_condition{condition="Ready",status="true"})',
                            "{{node}}", mapping([(1, "Siap", "green"), (0, "Mati", "red")]), w=12, h=7))
    p.append(timeseries(lay, "Pod aplikasi modern yang melayani", [
        target('sum by (app) (up{namespace="modern",job="observability/relnusa"})', "{{app}}")],
        w=6, h=7, decimals=0, stack=True, fill=60))
    p.append(timeseries(lay, "Replika search (autoscaling)", [
        target('max(kube_horizontalpodautoscaler_status_current_replicas{namespace="modern",horizontalpodautoscaler="search"})', "berjalan", "A"),
        target('max(kube_horizontalpodautoscaler_status_desired_replicas{namespace="modern",horizontalpodautoscaler="search"})', "diinginkan", "B")],
        w=6, h=7, decimals=0))
    p.append(row(lay, "Pembayaran dan bank"))
    p.append(stat(lay, "Circuit breaker ke bank", 'max(payment_circuit_state{namespace="modern"})', w=6, h=7, graph=False,
                  mappings=mapping([(0, "Tertutup (normal)", "green"), (1, "Setengah terbuka (uji coba)", "orange"),
                                    (2, "Terbuka (bank sedang dilindungi)", "red")]),
                  thr=thresholds("green", 1, "orange", 2, "red")))
    p.append(timeseries(lay, "Upaya pembayaran per detik menurut hasil", [
        target('sum by (outcome) (rate(payment_attempts_total{namespace="modern"}[30s]))', "{{outcome}}")],
        w=9, h=7, decimals=1, stack=True, fill=50,
        colors=[("success", COL_MODERN), ("timeout", "#D97706"), ("failure", "#B42318"), ("circuit_open", "#7C3AED"),
                ("error", "#6B7280")]))
    p.append(timeseries(lay, "Pembayaran menunggu di antrean", [
        target('max(payment_queue_pending{namespace="modern"})', "tertunda")], w=9, h=7, decimals=0))
    p.append(stat(lay, "Tagihan ganda yang dicegah", 'sum(bank_requests_total{namespace="bank",outcome="duplicate"}) or vector(0)',
                  w=6, h=5, graph=False, thr=thresholds("blue"), color_mode="value",
                  desc="Permintaan ulang dengan kunci idempotensi yang sama. Bank mengembalikan hasil lama, bukan menagih lagi."))
    p.append(stat(lay, "Mode bank simulasi (latensi dasar)", 'max(bank_configured_latency_ms{namespace="bank"})', w=6, h=5,
                  unit="ms", graph=False, thr=thresholds("green", 1000, "red"), color_mode="value"))
    p.append(timeseries(lay, "Waktu respons booking p95 (detik)", [
        target('histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="modern",service="booking",route="/api/bookings"}[1m])))', "booking"),
        target('histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="legacy",route="/api/bookings"}[1m])))', "monolith (pembanding)", "B")],
        w=12, h=5, unit="s", decimals=2, colors=[("booking", COL_MODERN), ("monolith (pembanding)", COL_LEGACY)]))
    p.append(row(lay, "Database PostgreSQL (CloudNativePG)"))
    p.append(state_timeline(lay, "Peran instance database", 'max by (pod) (1 - cnpg_pg_replication_in_recovery{namespace="modern"})',
                            "{{pod}}", mapping([(1, "Primary", "blue"), (0, "Replika", "green")]), w=12, h=6,
                            desc="Saat primary mati, salah satu replika naik menjadi primary."))
    p.append(timeseries(lay, "Jeda replikasi (detik)", [
        target('max by (pod) (cnpg_pg_replication_lag{namespace="modern"})', "{{pod}}")], w=6, h=6, unit="s", decimals=2))
    p.append(timeseries(lay, "Koneksi database aktif", [
        target('sum by (pod) (cnpg_backends_total{namespace="modern"})', "{{pod}}")], w=6, h=6, decimals=0))
    p.append(row(lay, "Cache pencarian dan rilis booking"))
    p.append(timeseries(lay, "Sumber jawaban pencarian", [
        target('sum by (source) (rate(search_cache_requests_total{namespace="modern"}[30s]))', "{{source}}")],
        w=8, h=7, unit="reqps", decimals=0, stack=True, fill=50,
        colors=[("cache", COL_MODERN), ("database", "#2563EB"), ("stale-cache", "#D97706")]))
    p.append(timeseries(lay, "Error booking per versi", [
        # The "or ... * 0" part draws a zero line per version while there are no errors yet.
        target('sum by (version) ('
               '(sum by (pod) (rate(http_requests_total{namespace="modern",service="booking",route="/api/bookings",code=~"5.."}[30s])) '
               'or sum by (pod) (rate(http_requests_total{namespace="modern",service="booking",route="/api/bookings"}[30s])) * 0) '
               '* on (pod) group_left (version) max by (pod, version) (relnusa_build_info{namespace="modern",service="booking"}))', "{{version}}")],
        w=8, h=7, unit="reqps", decimals=2, minv=0, softmax=1))
    p.append(timeseries(lay, "Pod booking per versi", [
        target('count by (version) (relnusa_build_info{namespace="modern",service="booking"})', "{{version}}")],
        w=8, h=7, decimals=0, stack=True, fill=60))
    return dashboard("relnusa-3", "RelNusa · 3 · Di dalam arsitektur modern", p)


def configmap(name, filename, dash):
    body = json.dumps(dash, ensure_ascii=False, indent=1)
    indented = "\n".join("    " + line for line in body.splitlines())
    return (f"apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: {name}\n  namespace: observability\n"
            f"  labels:\n    grafana_dashboard: \"1\"\n  annotations:\n    grafana_folder: RelNusa\n"
            f"data:\n  {filename}: |-\n{indented}\n")


def main():
    docs = [
        configmap("relnusa-dashboard-00", "relnusa-00-ringkasan.json", d00()),
        configmap("relnusa-dashboard-01", "relnusa-01-sebelum-sesudah.json", d01()),
        configmap("relnusa-dashboard-02", "relnusa-02-slo.json", d02()),
        configmap("relnusa-dashboard-03", "relnusa-03-modern.json", d03()),
    ]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("# Generated by tools/make_dashboards.py. Edit that file, not this one.\n" + "---\n".join(docs))
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
