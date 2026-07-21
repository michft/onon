import { useEffect, useMemo, useState } from "react";
import QRCode from "qrcode";
import { api, ApiError } from "./api";
import { MapCanvas } from "./MapCanvas";
import { nearestTrailLocation } from "./map-geometry";
import { useBrowserHostname } from "./map-manifest";
import { DISPLAY_PROFILES } from "./profiles";
import type { EditMode, MapManifest, Orientation, PrintScale, ProfileName, RecordingSummary, TrailOverlay } from "./types";

interface Pairing { code: string; expiresAt: string; qrPayload: string; qrImage: string }

export function App(): React.JSX.Element {
  const [manifest, setManifest] = useState<MapManifest | null>(null);
  const [recordings, setRecordings] = useState<RecordingSummary[]>([]);
  const [trail, setTrail] = useState<TrailOverlay | null>(null);
  const [locked, setLocked] = useState(true);
  const [bootstrapToken, setBootstrapToken] = useState("");
  const [profile, setProfile] = useState<ProfileName>("screen");
  const [mode, setMode] = useState<EditMode>("inspect");
  const [selectedWaypoint, setSelectedWaypoint] = useState<string | null>(null);
  const [selectedArrow, setSelectedArrow] = useState<string | null>(null);
  const [rangeStart, setRangeStart] = useState<number | null>(null);
  const [pairing, setPairing] = useState<Pairing | null>(null);
  const [orientation, setOrientation] = useState<Orientation>("portrait");
  const [scale, setScale] = useState<PrintScale>(10_000);
  const [center, setCenter] = useState<[number, number]>([151.12, -33.87]);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("Unlock the local workspace.");

  useEffect(() => {
    void api.manifest()
      .then((value) => setManifest(useBrowserHostname(value, window.location.hostname)))
      .catch((error: unknown) => setMessage(errorMessage(error)));
  }, []);

  const refreshRecordings = async (): Promise<void> => {
    try {
      const next = await api.recordings();
      setRecordings(next);
      setLocked(false);
    } catch (error) {
      if (error instanceof ApiError && error.status === 401) setLocked(true);
      else setMessage(errorMessage(error));
    }
  };
  useEffect(() => { void refreshRecordings(); }, []);

  const run = async (operation: () => Promise<void>): Promise<void> => {
    setBusy(true);
    try { await operation(); }
    catch (error) { setMessage(errorMessage(error)); }
    finally { setBusy(false); }
  };

  const unlock = (event: React.FormEvent): void => {
    event.preventDefault();
    void run(async () => {
      await api.adminSession(bootstrapToken);
      setBootstrapToken("");
      await refreshRecordings();
      setMessage("Workspace unlocked for this browser session.");
    });
  };

  const selectRecording = (recording: RecordingSummary): void => {
    void run(async () => {
      const next = recording.trailOverlayId
        ? await api.trail(recording.trailOverlayId)
        : await api.createTrail(recording.id);
      setTrail(next);
      setMessage(recording.trailOverlayId ? "Trail Overlay loaded." : "Trail Overlay derived; Raw Recording unchanged.");
      await refreshRecordings();
    });
  };

  const mapClick = (longitude: number, latitude: number): void => {
    if (!trail || mode === "inspect") return;
    void run(async () => {
      if (mode === "waypoint") {
        setTrail(await api.addWaypoint(trail.id, latitude, longitude));
        setMessage("Waypoint added at exact clicked coordinate.");
      } else if (mode === "move-waypoint") {
        if (!selectedWaypoint) throw new Error("Select a waypoint before moving it.");
        setTrail(await api.moveWaypoint(trail.id, selectedWaypoint, latitude, longitude));
        setMessage("Waypoint moved.");
      } else {
        const nearest = nearestTrailLocation(trail, longitude, latitude);
        if (mode === "arrow") {
          setTrail(await api.addArrow(trail.id, nearest.segmentIndex, nearest.position));
          setMessage("Direction Arrow snapped beside the Trail Overlay.");
        } else if (mode === "move-arrow") {
          if (!selectedArrow) throw new Error("Select a Direction Arrow before moving it.");
          setTrail(await api.moveArrow(trail.id, selectedArrow, nearest.segmentIndex, nearest.position));
          setMessage("Direction Arrow moved along the Trail Overlay.");
        } else if (mode === "trim-start") {
          setTrail(await api.operation(trail, { type: "trim_start", throughIndex: nearest.vertexIndex }));
          setMessage("Trail Overlay start trimmed; Raw Recording unchanged.");
        } else if (mode === "trim-end") {
          setTrail(await api.operation(trail, { type: "trim_end", fromIndex: nearest.vertexIndex }));
          setMessage("Trail Overlay end trimmed; Raw Recording unchanged.");
        } else if (rangeStart === null) {
          setRangeStart(nearest.vertexIndex);
          setMessage("Bad-section start selected. Click its end.");
          return;
        } else {
          const [fromIndex, toIndex] = [rangeStart, nearest.vertexIndex].sort((left, right) => left - right);
          setTrail(await api.operation(trail, { type: "remove_range", fromIndex: fromIndex ?? 0, toIndex: toIndex ?? 0 }));
          setRangeStart(null);
          setMessage("Bad section removed as a gap; Raw Recording unchanged.");
        }
      }
      setMode("inspect");
    });
  };

  const printConfig = useMemo(() => trail ? { scale, orientation, center } : null, [trail, scale, orientation, center]);

  if (!manifest) return <main className="loading"><h1>Onon</h1><p>{message}</p></main>;
  return (
    <main className="app-shell">
      <header className="topbar">
        <div><h1>Onon</h1><p>Local trail workspace · map {manifest.version}</p></div>
        <label>Display Profile
          <select value={profile} onChange={(event) => setProfile(event.target.value as ProfileName)}>
            {Object.values(DISPLAY_PROFILES).map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}
          </select>
        </label>
      </header>

      {locked ? (
        <section className="unlock panel">
          <h2>Unlock local workspace</h2>
          <form onSubmit={unlock}>
            <label>Bootstrap secret<input type="password" value={bootstrapToken} onChange={(event) => setBootstrapToken(event.target.value)} required /></label>
            <button disabled={busy}>Unlock</button>
          </form>
          <p className="status" role="status">{message}</p>
        </section>
      ) : (
        <div className="workspace">
          <aside className="sidebar">
            <section className="panel">
              <h2>Raw Recordings</h2>
              <button onClick={() => void refreshRecordings()} disabled={busy}>Refresh list</button>
              <ul className="recordings">
                {recordings.map((recording) => (
                  <li key={recording.id}>
                    <button className={trail?.recordingId === recording.id ? "selected" : ""} onClick={() => selectRecording(recording)} disabled={busy}>
                      <strong>{new Date(recording.startedAt).toLocaleString()}</strong>
                      <span>{recording.sampleCount} samples · {recording.deviceName}</span>
                      <small>{recording.trailOverlayId ? "Trail Overlay ready" : "Raw only"}</small>
                    </button>
                  </li>
                ))}
              </ul>
            </section>

            <section className="panel">
              <h2>Device Pairing</h2>
              <button disabled={busy} onClick={() => void run(async () => {
                const value = await api.createPairingCode();
                setPairing({ ...value, qrImage: await QRCode.toDataURL(value.qrPayload, { width: 180, margin: 1 }) });
              })}>Pair iPhone</button>
              {pairing && <div className="pairing"><img src={pairing.qrImage} alt={`Pairing QR code ${pairing.code}`} /><strong>{pairing.code}</strong><small>Expires {new Date(pairing.expiresAt).toLocaleTimeString()}</small></div>}
            </section>
          </aside>

          <section className="map-region">
            <MapCanvas manifest={manifest} profile={profile} trail={trail} mode={mode} print={printConfig} onMapClick={mapClick} onCenterChange={setCenter} />
            <div className="map-tools panel" aria-label="Trail editing tools">
              <h2>Trail tools</h2>
              <div className="button-row">
                <ToolButton value="waypoint" current={mode} set={setMode}>Add Waypoint</ToolButton>
                <ToolButton value="arrow" current={mode} set={setMode}>Add Arrow</ToolButton>
                <ToolButton value="trim-start" current={mode} set={setMode}>Trim start</ToolButton>
                <ToolButton value="trim-end" current={mode} set={setMode}>Trim end</ToolButton>
                <ToolButton value="remove-range" current={mode} set={setMode}>Remove section</ToolButton>
                <button disabled={!trail?.canUndo || busy} onClick={() => trail && void run(async () => setTrail(await api.history(trail.id, "undo")))}>Undo</button>
                <button disabled={!trail?.canRedo || busy} onClick={() => trail && void run(async () => setTrail(await api.history(trail.id, "redo")))}>Redo</button>
              </div>
              <p className="status" role="status">{busy ? "Working…" : message}</p>
            </div>
          </section>

          <aside className="sidebar right-sidebar">
            <SymbolEditor trail={trail} selectedWaypoint={selectedWaypoint} setSelectedWaypoint={setSelectedWaypoint} selectedArrow={selectedArrow} setSelectedArrow={setSelectedArrow} setMode={setMode} setTrail={setTrail} run={run} />
            <PrintPanel trail={trail} profile={profile} setProfile={setProfile} orientation={orientation} setOrientation={setOrientation} scale={scale} setScale={setScale} center={center} run={run} />
          </aside>
        </div>
      )}
    </main>
  );
}

function ToolButton(props: { value: EditMode; current: EditMode; set: (mode: EditMode) => void; children: React.ReactNode }): React.JSX.Element {
  return <button className={props.current === props.value ? "active" : ""} aria-pressed={props.current === props.value} onClick={() => props.set(props.current === props.value ? "inspect" : props.value)}>{props.children}</button>;
}

function SymbolEditor(props: {
  trail: TrailOverlay | null; selectedWaypoint: string | null; setSelectedWaypoint: (id: string | null) => void;
  selectedArrow: string | null; setSelectedArrow: (id: string | null) => void;
  setMode: (mode: EditMode) => void; setTrail: (trail: TrailOverlay) => void; run: (operation: () => Promise<void>) => Promise<void>;
}): React.JSX.Element {
  return <section className="panel"><h2>Symbols</h2>
    {!props.trail && <p>Select a recording.</p>}
    {props.trail?.waypoints.map((waypoint, index) => <div className="symbol-row" key={waypoint.id}>
      <label><input type="radio" name="waypoint" checked={props.selectedWaypoint === waypoint.id} onChange={() => props.setSelectedWaypoint(waypoint.id)} /> Waypoint {index + 1}</label>
      <button onClick={() => { props.setSelectedWaypoint(waypoint.id); props.setMode("move-waypoint"); }}>Move</button>
      <button className="danger" onClick={() => void props.run(async () => props.setTrail(await api.deleteWaypoint(props.trail?.id ?? "", waypoint.id)))}>Delete</button>
    </div>)}
    {props.trail?.directionArrows.map((arrow, index) => <div className="symbol-row" key={arrow.id}>
      <span>Arrow {index + 1} · {arrow.side}</span>
      <button className={props.selectedArrow === arrow.id ? "selected" : ""} onClick={() => { props.setSelectedArrow(arrow.id); props.setMode("move-arrow"); }}>Move</button>
      <button onClick={() => void props.run(async () => props.setTrail(await api.flipArrow(props.trail?.id ?? "", arrow.id, arrow.side === "left" ? "right" : "left")))}>Flip side</button>
      <button className="danger" onClick={() => void props.run(async () => props.setTrail(await api.deleteArrow(props.trail?.id ?? "", arrow.id)))}>Delete</button>
    </div>)}
  </section>;
}

function PrintPanel(props: {
  trail: TrailOverlay | null; profile: ProfileName; setProfile: (profile: ProfileName) => void;
  orientation: Orientation; setOrientation: (value: Orientation) => void;
  scale: PrintScale; setScale: (value: PrintScale) => void; center: [number, number];
  run: (operation: () => Promise<void>) => Promise<void>;
}): React.JSX.Element {
  return <section className="panel"><h2>A4 PDF</h2>
    <p>Dashed crop is exact printed map area. Pan map to reposition.</p>
    <label>Print profile<select value={props.profile} onChange={(event) => props.setProfile(event.target.value as ProfileName)}>
      {Object.values(DISPLAY_PROFILES).map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}
    </select></label>
    <label>Orientation<select value={props.orientation} onChange={(event) => props.setOrientation(event.target.value as Orientation)}><option value="portrait">Portrait</option><option value="landscape">Landscape</option></select></label>
    <label>Scale<select value={props.scale} onChange={(event) => props.setScale(Number(event.target.value) as PrintScale)}><option value="10000">1:10,000</option><option value="15000">1:15,000</option><option value="25000">1:25,000</option></select></label>
    <button disabled={!props.trail} onClick={() => props.trail && void props.run(async () => {
      const pdf = await api.exportPdf({ trailOverlayId: props.trail?.id ?? "", profile: props.profile, orientation: props.orientation, scale: props.scale, center: props.center });
      const url = URL.createObjectURL(pdf);
      const anchor = document.createElement("a");
      anchor.href = url; anchor.download = "onon-trail.pdf"; anchor.click();
      window.setTimeout(() => URL.revokeObjectURL(url), 1_000);
    })}>Export PDF</button>
  </section>;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message.replaceAll("_", " ") : "Unexpected error";
}
