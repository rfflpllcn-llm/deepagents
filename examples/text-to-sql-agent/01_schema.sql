-- =============================================================================
-- Literary RAG System Schema v2
-- Revised schema for Céline's "Voyage au bout de la nuit" and other works
-- =============================================================================

-- 1) WORKS TABLE
-- Master record for literary works (language-independent)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS works (
    work_id BIGSERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    author TEXT NOT NULL,
    notes TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_works_title_author
ON works (title, author);


-- 2) EDITIONS TABLE
-- Specific editions/translations of a work
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS editions (
    edition_id BIGSERIAL PRIMARY KEY,
    work_id BIGINT NOT NULL REFERENCES works(work_id),
    language CHAR(2) NOT NULL,
    publisher TEXT,
    year INTEGER,
    isbn TEXT,
    anna_archive_id TEXT,
    notes TEXT,

    -- Validate publication year is plausible
    CONSTRAINT editions_year_range
        CHECK (year IS NULL OR year BETWEEN 1400 AND 2100)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_editions_identity
ON editions (work_id, language, publisher, anna_archive_id);


-- 3) CHUNKS TABLE
-- Raw text chunks extracted from OCR/PDF with bounding boxes
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chunks (
    chunk_id BIGSERIAL PRIMARY KEY,

    edition_id BIGINT NOT NULL
        REFERENCES editions (edition_id)
        ON DELETE CASCADE,

    -- Stable identifier for cross-referencing (e.g., "FR77")
    line_id TEXT NOT NULL,

    page INTEGER NOT NULL CHECK (page > 0),
    line_no INTEGER NOT NULL CHECK (line_no > 0),

    -- Bounding box: [x0, y0, x1, y1]
    box JSONB NOT NULL,
    text TEXT NOT NULL,

    -- Optional: hash for deduplication/change detection
    text_hash TEXT GENERATED ALWAYS AS (md5(text)) STORED,

    -- Validate box is a 4-element numeric array
    CONSTRAINT chunks_box_is_4nums
        CHECK (
            jsonb_typeof(box) = 'array'
            AND jsonb_array_length(box) = 4
            AND jsonb_typeof(box->0) = 'number'
            AND jsonb_typeof(box->1) = 'number'
            AND jsonb_typeof(box->2) = 'number'
            AND jsonb_typeof(box->3) = 'number'
        ),

    -- Position uniqueness within edition
    CONSTRAINT chunks_unique_pos
        UNIQUE (edition_id, page, line_no)
);

-- Primary lookup index
CREATE INDEX IF NOT EXISTS idx_chunks_edition_page_line
ON chunks (edition_id, page, line_no);

-- Full-text search (language-agnostic for multi-work support)
CREATE INDEX IF NOT EXISTS idx_chunks_text_gin
ON chunks USING gin (to_tsvector('simple', text));

-- line_id uniqueness within edition (for FK from semantic_chunk_members)
CREATE UNIQUE INDEX IF NOT EXISTS uq_chunks_edition_lineid
ON chunks (edition_id, line_id);

-- Hash lookup for deduplication
CREATE INDEX IF NOT EXISTS idx_chunks_text_hash
ON chunks (text_hash);


-- 4) SEMANTIC_CHUNKS TABLE
-- Semantically coherent groupings of raw chunks
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS semantic_chunks (
    sc_pk BIGSERIAL PRIMARY KEY,

    edition_id BIGINT NOT NULL
        REFERENCES editions (edition_id)
        ON DELETE CASCADE,

    -- Semantic chunk identifier (e.g., "SC_001")
    sc_id TEXT NOT NULL,

    -- Page span
    page_start INTEGER,
    page_end INTEGER,

    -- Text variants for different purposes
    embedding_text TEXT,      -- Optimized for embedding models
    embedding_summary TEXT,   -- Condensed version for retrieval
    paraphrase TEXT,          -- Rewritten version (Italian per your spec)

    -- Statistics
    word_count INTEGER,
    sentence_count INTEGER,

    -- Extensible metadata blob:
    -- {
    --   "register": "...",
    --   "interpretive_layers": [...],
    --   "retrieval_tags": [...],
    --   "context_links": [...],
    --   "keywords": {...},
    --   "questions": [...]
    -- }
    meta JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),

    CONSTRAINT uq_semantic_chunks UNIQUE (edition_id, sc_id),
    CONSTRAINT semantic_chunks_page_order
        CHECK (page_start IS NULL OR page_end IS NULL OR page_start <= page_end)
);

-- Edition lookup
CREATE INDEX IF NOT EXISTS idx_semantic_chunks_edition
ON semantic_chunks (edition_id);

-- JSONB index for tag-based queries
CREATE INDEX IF NOT EXISTS idx_semantic_chunks_meta_gin
ON semantic_chunks USING gin (meta jsonb_path_ops);


-- 5) SEMANTIC_CHUNK_MEMBERS TABLE
-- Junction table linking semantic chunks to their constituent raw chunks
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS semantic_chunk_members (
    sc_pk BIGINT NOT NULL
        REFERENCES semantic_chunks (sc_pk)
        ON DELETE CASCADE,

    -- Denormalized for query convenience and composite FK
    edition_id BIGINT NOT NULL
        REFERENCES editions (edition_id)
        ON DELETE CASCADE,

    line_id TEXT NOT NULL,
    ord INTEGER NOT NULL CHECK (ord > 0),

    PRIMARY KEY (sc_pk, line_id),

    -- Ensure the referenced chunk exists
    CONSTRAINT fk_member_chunk
        FOREIGN KEY (edition_id, line_id)
        REFERENCES chunks (edition_id, line_id)
        ON DELETE CASCADE
);

-- Ordering within a semantic chunk
CREATE INDEX IF NOT EXISTS idx_members_sc_ord
ON semantic_chunk_members (sc_pk, ord);

-- Reverse lookup: find all semantic chunks containing a given line
CREATE INDEX IF NOT EXISTS idx_members_edition_lineid
ON semantic_chunk_members (edition_id, line_id);


-- 6) CONSISTENCY TRIGGER
-- Ensures semantic_chunk_members.edition_id matches parent semantic_chunk
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_member_edition_consistency()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.edition_id != (
        SELECT edition_id FROM semantic_chunks WHERE sc_pk = NEW.sc_pk
    ) THEN
        RAISE EXCEPTION 'edition_id mismatch: member has %, parent semantic_chunk has %',
            NEW.edition_id,
            (SELECT edition_id FROM semantic_chunks WHERE sc_pk = NEW.sc_pk);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_member_edition_consistency ON semantic_chunk_members;
CREATE TRIGGER trg_member_edition_consistency
    BEFORE INSERT OR UPDATE ON semantic_chunk_members
    FOR EACH ROW
    EXECUTE FUNCTION check_member_edition_consistency();


-- 7) UPDATED_AT TRIGGER
-- Auto-update timestamp on semantic_chunks modification
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_semantic_chunks_updated_at ON semantic_chunks;
CREATE TRIGGER trg_semantic_chunks_updated_at
    BEFORE UPDATE ON semantic_chunks
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();


-- =============================================================================
-- SEED DATA
-- =============================================================================

-- Insert work (idempotent)
INSERT INTO works (title, author)
VALUES ('Voyage au bout de la nuit', 'Louis-Ferdinand Céline')
ON CONFLICT (title, author) DO NOTHING;

-- Insert edition (idempotent)
INSERT INTO editions (work_id, language, publisher, year, anna_archive_id, notes)
SELECT
    w.work_id,
    'fr',
    'Gallimard',
    1986,
    '6958e728898572b5ccc0031ac6c40c21',
    $$Scanné et relu d'après un exemplaire des éditions Gallimard du 24 janvier 1986, collection Folio (les notes appartiennent à une édition ultérieure). La ponctuation a été scrupuleusement vérifiée sur cet exemplaire, qui semble parfois fautif ; il conviendrait alors de se reporter à l'édition de La Pléiade. Tous les retours à la lignes n'ont pas été vérifiés ; il est donc possible (mais rarement) que quelques lignes forment un paragraphe alors qu'elles devraient s'enchaîner au précédent. Enfin, si vous souhaitez diffuser ce texte, ne le modifiez pas sans avoir vérifié vos corrections sur l'original en papier.$$
FROM works w
WHERE w.title = 'Voyage au bout de la nuit'
  AND w.author = 'Louis-Ferdinand Céline'
ON CONFLICT (work_id, language, publisher, anna_archive_id) DO NOTHING;


-- =============================================================================
-- 8) MICRO_UNITS TABLE
-- Narrative micro-units: higher-level groupings of semantic chunks
-- representing coherent narrative segments with interpretive metadata
-- =============================================================================
CREATE TABLE IF NOT EXISTS micro_units (
    mu_pk BIGSERIAL PRIMARY KEY,

    edition_id BIGINT NOT NULL
        REFERENCES editions (edition_id)
        ON DELETE CASCADE,

    -- Micro-unit identifier (e.g., "MU_001")
    unit_id TEXT NOT NULL,

    -- Page span
    page_start INTEGER,
    page_end INTEGER,

    -- Structured summary
    -- {
    --   "what_happens": "...",
    --   "narrative_function": "apertura_sezione|sviluppo|climax|risoluzione|transizione|...",
    --   "significance": "..."
    -- }
    summary JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- Character interaction dynamics
    -- [
    --   {
    --     "from": "Ganate",
    --     "to": "Bardamu",
    --     "relation_type": "amicizia_intellettuale",
    --     "interaction": "provocazione_dialettica",
    --     "evolution": "..."
    --   }
    -- ]
    character_dynamics JSONB NOT NULL DEFAULT '[]'::jsonb,

    -- Thematic/narrative threads this unit participates in
    -- ["incontro_ganate", "critica_modernità", "contesto_prebellico"]
    story_threads TEXT[] NOT NULL DEFAULT '{}',

    -- Extensible metadata for future enrichments
    meta JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),

    CONSTRAINT uq_micro_units UNIQUE (edition_id, unit_id),
    CONSTRAINT micro_units_page_order
        CHECK (page_start IS NULL OR page_end IS NULL OR page_start <= page_end),
    CONSTRAINT micro_units_character_dynamics_is_array
        CHECK (jsonb_typeof(character_dynamics) = 'array')
);

-- Edition lookup
CREATE INDEX IF NOT EXISTS idx_micro_units_edition
ON micro_units (edition_id);

-- Story thread lookup (GIN for array containment queries)
CREATE INDEX IF NOT EXISTS idx_micro_units_story_threads
ON micro_units USING gin (story_threads);

-- Character dynamics queries (e.g., find all units involving "Bardamu")
CREATE INDEX IF NOT EXISTS idx_micro_units_character_dynamics
ON micro_units USING gin (character_dynamics jsonb_path_ops);

-- Narrative function lookup
CREATE INDEX IF NOT EXISTS idx_micro_units_narrative_function
ON micro_units ((summary->>'narrative_function'));


-- 9) MICRO_UNIT_MEMBERS TABLE
-- Junction table linking micro-units to their constituent semantic chunks
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS micro_unit_members (
    mu_pk BIGINT NOT NULL
        REFERENCES micro_units (mu_pk)
        ON DELETE CASCADE,

    -- Denormalized for query convenience and composite FK
    edition_id BIGINT NOT NULL
        REFERENCES editions (edition_id)
        ON DELETE CASCADE,

    sc_id TEXT NOT NULL,
    ord INTEGER NOT NULL CHECK (ord > 0),

    PRIMARY KEY (mu_pk, sc_id),

    -- Ensure the referenced semantic chunk exists
    CONSTRAINT fk_mu_member_semantic_chunk
        FOREIGN KEY (edition_id, sc_id)
        REFERENCES semantic_chunks (edition_id, sc_id)
        ON DELETE CASCADE
);

-- Ordering within a micro-unit
CREATE INDEX IF NOT EXISTS idx_mu_members_ord
ON micro_unit_members (mu_pk, ord);

-- Reverse lookup: find all micro-units containing a given semantic chunk
CREATE INDEX IF NOT EXISTS idx_mu_members_edition_scid
ON micro_unit_members (edition_id, sc_id);


-- 10) CONSISTENCY TRIGGER FOR MICRO_UNIT_MEMBERS
-- Ensures micro_unit_members.edition_id matches parent micro_unit
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_mu_member_edition_consistency()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.edition_id != (
        SELECT edition_id FROM micro_units WHERE mu_pk = NEW.mu_pk
    ) THEN
        RAISE EXCEPTION 'edition_id mismatch: member has %, parent micro_unit has %',
            NEW.edition_id,
            (SELECT edition_id FROM micro_units WHERE mu_pk = NEW.mu_pk);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_mu_member_edition_consistency ON micro_unit_members;
CREATE TRIGGER trg_mu_member_edition_consistency
    BEFORE INSERT OR UPDATE ON micro_unit_members
    FOR EACH ROW
    EXECUTE FUNCTION check_mu_member_edition_consistency();


-- 11) UPDATED_AT TRIGGER FOR MICRO_UNITS
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_micro_units_updated_at ON micro_units;
CREATE TRIGGER trg_micro_units_updated_at
    BEFORE UPDATE ON micro_units
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();


-- =============================================================================
-- USEFUL VIEWS
-- =============================================================================

-- Semantic chunk with member count and page range
CREATE OR REPLACE VIEW v_semantic_chunks_summary AS
SELECT
    sc.sc_pk,
    sc.edition_id,
    sc.sc_id,
    sc.page_start,
    sc.page_end,
    sc.word_count,
    sc.sentence_count,
    COUNT(scm.line_id) AS member_count,
    array_agg(scm.line_id ORDER BY scm.ord) AS member_line_ids,
    sc.created_at,
    sc.updated_at
FROM semantic_chunks sc
LEFT JOIN semantic_chunk_members scm ON sc.sc_pk = scm.sc_pk
GROUP BY sc.sc_pk;

-- Full chunk text for a semantic chunk (concatenated in order)
CREATE OR REPLACE VIEW v_semantic_chunk_full_text AS
SELECT
    sc.sc_pk,
    sc.sc_id,
    sc.edition_id,
    string_agg(c.text, ' ' ORDER BY scm.ord) AS full_text
FROM semantic_chunks sc
JOIN semantic_chunk_members scm ON sc.sc_pk = scm.sc_pk
JOIN chunks c ON c.edition_id = scm.edition_id AND c.line_id = scm.line_id
GROUP BY sc.sc_pk, sc.sc_id, sc.edition_id;

-- Micro-unit summary with member count and semantic chunk IDs
CREATE OR REPLACE VIEW v_micro_units_summary AS
SELECT
    mu.mu_pk,
    mu.edition_id,
    mu.unit_id,
    mu.page_start,
    mu.page_end,
    mu.summary->>'what_happens' AS what_happens,
    mu.summary->>'narrative_function' AS narrative_function,
    mu.summary->>'significance' AS significance,
    mu.story_threads,
    COUNT(mum.sc_id) AS semantic_chunk_count,
    array_agg(mum.sc_id ORDER BY mum.ord) AS semantic_chunk_ids,
    mu.created_at,
    mu.updated_at
FROM micro_units mu
LEFT JOIN micro_unit_members mum ON mu.mu_pk = mum.mu_pk
GROUP BY mu.mu_pk;

-- Character interactions flattened for analysis
CREATE OR REPLACE VIEW v_character_interactions AS
SELECT
    mu.mu_pk,
    mu.edition_id,
    mu.unit_id,
    mu.page_start,
    mu.page_end,
    cd->>'from' AS character_from,
    cd->>'to' AS character_to,
    cd->>'relation_type' AS relation_type,
    cd->>'interaction' AS interaction,
    cd->>'evolution' AS evolution
FROM micro_units mu
CROSS JOIN LATERAL jsonb_array_elements(mu.character_dynamics) AS cd;

-- Story thread participation (which units belong to which threads)
CREATE OR REPLACE VIEW v_story_thread_units AS
SELECT
    mu.edition_id,
    unnest(mu.story_threads) AS story_thread,
    mu.mu_pk,
    mu.unit_id,
    mu.page_start,
    mu.page_end,
    mu.summary->>'what_happens' AS what_happens
FROM micro_units mu
ORDER BY story_thread, mu.page_start;