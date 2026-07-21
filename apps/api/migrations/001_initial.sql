CREATE TABLE IF NOT EXISTS schema_migrations (
  version integer PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE devices (
  id uuid PRIMARY KEY,
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
  token_hash text NOT NULL UNIQUE,
  paired_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz,
  revoked_at timestamptz
);

CREATE TABLE pairing_codes (
  id uuid PRIMARY KEY,
  code_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX pairing_codes_lookup ON pairing_codes (code_hash, expires_at);

CREATE TABLE raw_recordings (
  id uuid PRIMARY KEY,
  device_id uuid NOT NULL REFERENCES devices(id),
  client_recording_id uuid NOT NULL,
  started_at timestamptz NOT NULL,
  finished_at timestamptz NOT NULL,
  payload_sha256 text NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (device_id, client_recording_id),
  CHECK (finished_at >= started_at)
);

CREATE TABLE raw_samples (
  recording_id uuid NOT NULL REFERENCES raw_recordings(id),
  sample_index integer NOT NULL CHECK (sample_index >= 0),
  observed_at timestamptz NOT NULL,
  latitude double precision NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude double precision NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  horizontal_accuracy_m double precision NOT NULL CHECK (horizontal_accuracy_m >= 0),
  altitude_m double precision,
  vertical_accuracy_m double precision CHECK (vertical_accuracy_m IS NULL OR vertical_accuracy_m >= 0),
  speed_mps double precision,
  course_degrees double precision CHECK (course_degrees IS NULL OR course_degrees BETWEEN 0 AND 360),
  PRIMARY KEY (recording_id, sample_index)
);

CREATE TABLE raw_waypoint_observations (
  id uuid PRIMARY KEY,
  recording_id uuid NOT NULL REFERENCES raw_recordings(id),
  observation_index integer NOT NULL CHECK (observation_index >= 0),
  observed_at timestamptz NOT NULL,
  latitude double precision NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude double precision NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  horizontal_accuracy_m double precision NOT NULL CHECK (horizontal_accuracy_m >= 0),
  label text,
  UNIQUE (recording_id, observation_index)
);

CREATE TABLE sync_receipts (
  device_id uuid NOT NULL REFERENCES devices(id),
  idempotency_key text NOT NULL,
  request_sha256 text NOT NULL,
  recording_id uuid NOT NULL REFERENCES raw_recordings(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (device_id, idempotency_key)
);

CREATE TABLE trail_overlays (
  id uuid PRIMARY KEY,
  recording_id uuid NOT NULL UNIQUE REFERENCES raw_recordings(id),
  name text NOT NULL,
  current_revision integer NOT NULL DEFAULT 0 CHECK (current_revision >= 0),
  undo_stack jsonb NOT NULL DEFAULT '[]'::jsonb,
  redo_stack jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE trail_revisions (
  trail_id uuid NOT NULL REFERENCES trail_overlays(id) ON DELETE CASCADE,
  revision integer NOT NULL CHECK (revision >= 0),
  source_segments jsonb NOT NULL,
  operation jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (trail_id, revision),
  CHECK (jsonb_array_length(source_segments) >= 1)
);

CREATE TABLE editable_waypoints (
  id uuid PRIMARY KEY,
  trail_id uuid NOT NULL REFERENCES trail_overlays(id) ON DELETE CASCADE,
  source_observation_id uuid REFERENCES raw_waypoint_observations(id),
  latitude double precision NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude double precision NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  label text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TYPE arrow_side AS ENUM ('left', 'right');

CREATE TABLE direction_arrows (
  id uuid PRIMARY KEY,
  trail_id uuid NOT NULL REFERENCES trail_overlays(id) ON DELETE CASCADE,
  source_start_sample_index integer NOT NULL CHECK (source_start_sample_index >= 0),
  source_end_sample_index integer NOT NULL CHECK (source_end_sample_index >= 0),
  segment_fraction double precision NOT NULL CHECK (segment_fraction BETWEEN 0 AND 1),
  side arrow_side NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE map_versions (
  id uuid PRIMARY KEY,
  version text NOT NULL UNIQUE,
  archive_path text NOT NULL,
  source_url text NOT NULL,
  source_sha256 text NOT NULL,
  bounds jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  activated_at timestamptz,
  retired_at timestamptz
);

CREATE UNIQUE INDEX one_active_map_version
  ON map_versions ((activated_at IS NOT NULL AND retired_at IS NULL))
  WHERE activated_at IS NOT NULL AND retired_at IS NULL;

CREATE FUNCTION reject_raw_mutation() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'raw recording data is immutable';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER raw_recordings_immutable BEFORE UPDATE OR DELETE ON raw_recordings
  FOR EACH ROW EXECUTE FUNCTION reject_raw_mutation();
CREATE TRIGGER raw_samples_immutable BEFORE UPDATE OR DELETE ON raw_samples
  FOR EACH ROW EXECUTE FUNCTION reject_raw_mutation();
CREATE TRIGGER raw_waypoints_immutable BEFORE UPDATE OR DELETE ON raw_waypoint_observations
  FOR EACH ROW EXECUTE FUNCTION reject_raw_mutation();
