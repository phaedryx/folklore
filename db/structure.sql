SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: asset_tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asset_tags (
    id bigint NOT NULL,
    asset_id bigint NOT NULL,
    tag_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: asset_tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.asset_tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: asset_tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.asset_tags_id_seq OWNED BY public.asset_tags.id;


--
-- Name: assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assets (
    id bigint NOT NULL,
    owner_id bigint NOT NULL,
    slug character varying NOT NULL,
    dir text NOT NULL,
    name character varying NOT NULL,
    content text,
    content_type character varying,
    lock_version integer DEFAULT 0 NOT NULL,
    status character varying,
    stale_after date,
    verified_at timestamp(6) without time zone,
    verified_by_token_id bigint,
    verified_by_agent character varying,
    deleted_at timestamp(6) without time zone,
    created_by_token_id bigint,
    created_by_agent character varying,
    updated_by_token_id bigint,
    updated_by_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    content_tsv tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, COALESCE(content, ''::text))) STORED,
    CONSTRAINT assets_content_size_check CHECK ((octet_length(content) <= 1048576)),
    CONSTRAINT assets_dir_length_check CHECK ((char_length(dir) <= 1024)),
    CONSTRAINT assets_name_length_check CHECK ((char_length((name)::text) <= 255)),
    CONSTRAINT assets_status_check CHECK (((status IS NULL) OR ((status)::text = ANY (ARRAY[('open'::character varying)::text, ('done'::character varying)::text]))))
);


--
-- Name: assets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.assets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: assets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.assets_id_seq OWNED BY public.assets.id;


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id bigint NOT NULL,
    actor_user_id bigint,
    actor_token_id bigint,
    actor_agent character varying,
    asset_id bigint,
    action character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT events_action_check CHECK (((action)::text = ANY ((ARRAY['asset_created'::character varying, 'asset_updated'::character varying, 'asset_deleted'::character varying, 'asset_restored'::character varying, 'tag_added'::character varying, 'tag_removed'::character varying, 'task_added'::character varying, 'task_claimed'::character varying, 'task_completed'::character varying, 'task_failed'::character varying, 'task_cancelled'::character varying, 'task_lease_expired'::character varying, 'version_restored'::character varying, 'asset_verified'::character varying, 'asset_review_scheduled'::character varying, 'asset_status_set'::character varying, 'asset_imported'::character varying, 'asset_moved'::character varying])::text[])))
);


--
-- Name: events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.events_id_seq OWNED BY public.events.id;


--
-- Name: links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.links (
    id bigint NOT NULL,
    src_asset_id bigint NOT NULL,
    dst_asset_id bigint,
    dst_ref character varying NOT NULL,
    kind character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT links_kind_check CHECK (((kind)::text = 'wikilink'::text))
);


--
-- Name: links_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.links_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.links_id_seq OWNED BY public.links.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: search_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.search_logs (
    id bigint NOT NULL,
    query text NOT NULL,
    filters jsonb DEFAULT '{}'::jsonb NOT NULL,
    result_slugs character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    token_id bigint,
    followed_slug character varying,
    created_at timestamp(6) without time zone NOT NULL,
    actor_agent character varying
);


--
-- Name: search_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.search_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: search_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.search_logs_id_seq OWNED BY public.search_logs.id;


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tags (
    id bigint NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT tags_name_length_check CHECK ((char_length((name)::text) <= 100))
);


--
-- Name: tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tags_id_seq OWNED BY public.tags.id;


--
-- Name: tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasks (
    asset_id bigint NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    claimed_by_token_id bigint,
    claimed_by_user_id bigint,
    claimed_by_agent character varying,
    lease_until timestamp with time zone,
    attempts integer DEFAULT 0 NOT NULL,
    outcome_note text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT tasks_claim_check CHECK (((((status)::text = 'in_progress'::text) AND (claimed_by_user_id IS NOT NULL) AND (claimed_by_agent IS NOT NULL) AND (lease_until IS NOT NULL)) OR (((status)::text <> 'in_progress'::text) AND (claimed_by_user_id IS NULL) AND (claimed_by_token_id IS NULL) AND (claimed_by_agent IS NULL) AND (lease_until IS NULL)))),
    CONSTRAINT tasks_outcome_note_length_check CHECK ((char_length(outcome_note) <= 10000)),
    CONSTRAINT tasks_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('in_progress'::character varying)::text, ('done'::character varying)::text, ('failed'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tokens (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    agent_name character varying NOT NULL,
    token_digest character varying NOT NULL,
    scopes character varying[] DEFAULT '{read,write}'::character varying[] NOT NULL,
    last_used_at timestamp(6) without time zone,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    shared boolean DEFAULT false NOT NULL
);


--
-- Name: tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tokens_id_seq OWNED BY public.tokens.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    handle character varying,
    email character varying NOT NULL,
    name character varying,
    password_digest character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.versions (
    id bigint NOT NULL,
    asset_id bigint NOT NULL,
    content text,
    content_type character varying,
    actor_user_id bigint,
    actor_token_id bigint,
    actor_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    content_tsv tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, COALESCE(content, ''::text))) STORED
);


--
-- Name: versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.versions_id_seq OWNED BY public.versions.id;


--
-- Name: asset_tags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_tags ALTER COLUMN id SET DEFAULT nextval('public.asset_tags_id_seq'::regclass);


--
-- Name: assets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets ALTER COLUMN id SET DEFAULT nextval('public.assets_id_seq'::regclass);


--
-- Name: events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events ALTER COLUMN id SET DEFAULT nextval('public.events_id_seq'::regclass);


--
-- Name: links id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.links ALTER COLUMN id SET DEFAULT nextval('public.links_id_seq'::regclass);


--
-- Name: search_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_logs ALTER COLUMN id SET DEFAULT nextval('public.search_logs_id_seq'::regclass);


--
-- Name: tags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags ALTER COLUMN id SET DEFAULT nextval('public.tags_id_seq'::regclass);


--
-- Name: tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens ALTER COLUMN id SET DEFAULT nextval('public.tokens_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions ALTER COLUMN id SET DEFAULT nextval('public.versions_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: asset_tags asset_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_tags
    ADD CONSTRAINT asset_tags_pkey PRIMARY KEY (id);


--
-- Name: assets assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: links links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.links
    ADD CONSTRAINT links_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: search_logs search_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_logs
    ADD CONSTRAINT search_logs_pkey PRIMARY KEY (id);


--
-- Name: tags tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (id);


--
-- Name: tasks tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (asset_id);


--
-- Name: tokens tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT tokens_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: versions versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions
    ADD CONSTRAINT versions_pkey PRIMARY KEY (id);


--
-- Name: index_asset_tags_on_asset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_asset_tags_on_asset_id ON public.asset_tags USING btree (asset_id);


--
-- Name: index_asset_tags_on_asset_id_and_tag_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_asset_tags_on_asset_id_and_tag_id ON public.asset_tags USING btree (asset_id, tag_id);


--
-- Name: index_asset_tags_on_tag_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_asset_tags_on_tag_id ON public.asset_tags USING btree (tag_id);


--
-- Name: index_assets_on_content_tsv; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_content_tsv ON public.assets USING gin (content_tsv);


--
-- Name: index_assets_on_created_by_token_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_created_by_token_id ON public.assets USING btree (created_by_token_id);


--
-- Name: index_assets_on_dir; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_dir ON public.assets USING btree (dir text_pattern_ops);


--
-- Name: index_assets_on_dir_and_name_live; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_assets_on_dir_and_name_live ON public.assets USING btree (dir, name) WHERE (deleted_at IS NULL);


--
-- Name: index_assets_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_name ON public.assets USING gin (name public.gin_trgm_ops);


--
-- Name: index_assets_on_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_owner_id ON public.assets USING btree (owner_id);


--
-- Name: index_assets_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_assets_on_slug ON public.assets USING btree (slug);


--
-- Name: index_assets_on_stale_after; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_stale_after ON public.assets USING btree (stale_after);


--
-- Name: index_assets_on_updated_by_token_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_updated_by_token_id ON public.assets USING btree (updated_by_token_id);


--
-- Name: index_assets_on_verified_by_token_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_verified_by_token_id ON public.assets USING btree (verified_by_token_id);


--
-- Name: index_events_on_actor_token_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_actor_token_id ON public.events USING btree (actor_token_id);


--
-- Name: index_events_on_actor_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_actor_user_id_and_created_at ON public.events USING btree (actor_user_id, created_at);


--
-- Name: index_events_on_asset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_asset_id ON public.events USING btree (asset_id);


--
-- Name: index_events_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_created_at ON public.events USING btree (created_at);


--
-- Name: index_links_on_dst_asset_id_and_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_links_on_dst_asset_id_and_kind ON public.links USING btree (dst_asset_id, kind);


--
-- Name: index_links_on_dst_ref_and_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_links_on_dst_ref_and_kind ON public.links USING btree (dst_ref, kind);


--
-- Name: index_links_on_src_asset_id_and_dst_ref_and_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_links_on_src_asset_id_and_dst_ref_and_kind ON public.links USING btree (src_asset_id, dst_ref, kind);


--
-- Name: index_search_logs_on_token_id_and_actor_agent_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_search_logs_on_token_id_and_actor_agent_and_created_at ON public.search_logs USING btree (token_id, actor_agent, created_at);


--
-- Name: index_search_logs_on_token_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_search_logs_on_token_id_and_created_at ON public.search_logs USING btree (token_id, created_at);


--
-- Name: index_tags_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tags_on_name ON public.tags USING btree (name);


--
-- Name: index_tasks_on_claimed_by_token_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_claimed_by_token_id ON public.tasks USING btree (claimed_by_token_id);


--
-- Name: index_tasks_on_claimed_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_claimed_by_user_id ON public.tasks USING btree (claimed_by_user_id);


--
-- Name: index_tasks_on_status_and_lease_until; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_status_and_lease_until ON public.tasks USING btree (status, lease_until);


--
-- Name: index_tokens_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tokens_on_token_digest ON public.tokens USING btree (token_digest);


--
-- Name: index_tokens_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tokens_on_user_id ON public.tokens USING btree (user_id);


--
-- Name: index_tokens_on_user_id_and_agent_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tokens_on_user_id_and_agent_name ON public.tokens USING btree (user_id, agent_name);


--
-- Name: index_users_on_handle; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_handle ON public.users USING btree (handle);


--
-- Name: index_users_on_lower_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_lower_email ON public.users USING btree (lower((email)::text));


--
-- Name: index_versions_on_actor_token_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_versions_on_actor_token_id ON public.versions USING btree (actor_token_id);


--
-- Name: index_versions_on_actor_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_versions_on_actor_user_id ON public.versions USING btree (actor_user_id);


--
-- Name: index_versions_on_asset_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_versions_on_asset_id_and_created_at ON public.versions USING btree (asset_id, created_at);


--
-- Name: index_versions_on_content_tsv; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_versions_on_content_tsv ON public.versions USING gin (content_tsv);


--
-- Name: versions fk_rails_1ced22f94f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions
    ADD CONSTRAINT fk_rails_1ced22f94f FOREIGN KEY (actor_token_id) REFERENCES public.tokens(id);


--
-- Name: tasks fk_rails_36e6d6a645; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_36e6d6a645 FOREIGN KEY (claimed_by_token_id) REFERENCES public.tokens(id);


--
-- Name: links fk_rails_3c4f6509ee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.links
    ADD CONSTRAINT fk_rails_3c4f6509ee FOREIGN KEY (dst_asset_id) REFERENCES public.assets(id);


--
-- Name: asset_tags fk_rails_3c793aa884; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_tags
    ADD CONSTRAINT fk_rails_3c793aa884 FOREIGN KEY (tag_id) REFERENCES public.tags(id);


--
-- Name: events fk_rails_3d0f7ca0e7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_3d0f7ca0e7 FOREIGN KEY (asset_id) REFERENCES public.assets(id);


--
-- Name: tasks fk_rails_546c3973b4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_546c3973b4 FOREIGN KEY (asset_id) REFERENCES public.assets(id);


--
-- Name: assets fk_rails_54e6bec072; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT fk_rails_54e6bec072 FOREIGN KEY (verified_by_token_id) REFERENCES public.tokens(id);


--
-- Name: assets fk_rails_6490b99b9f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT fk_rails_6490b99b9f FOREIGN KEY (updated_by_token_id) REFERENCES public.tokens(id);


--
-- Name: tasks fk_rails_6b18941525; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_6b18941525 FOREIGN KEY (claimed_by_user_id) REFERENCES public.users(id);


--
-- Name: events fk_rails_946a2f1e76; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_946a2f1e76 FOREIGN KEY (actor_token_id) REFERENCES public.tokens(id);


--
-- Name: versions fk_rails_9df39143b0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions
    ADD CONSTRAINT fk_rails_9df39143b0 FOREIGN KEY (actor_user_id) REFERENCES public.users(id);


--
-- Name: assets fk_rails_aa37446634; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT fk_rails_aa37446634 FOREIGN KEY (created_by_token_id) REFERENCES public.tokens(id);


--
-- Name: tokens fk_rails_ac8a5d0441; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT fk_rails_ac8a5d0441 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: versions fk_rails_ae0c233c78; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions
    ADD CONSTRAINT fk_rails_ae0c233c78 FOREIGN KEY (asset_id) REFERENCES public.assets(id);


--
-- Name: asset_tags fk_rails_b129c8f8c6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_tags
    ADD CONSTRAINT fk_rails_b129c8f8c6 FOREIGN KEY (asset_id) REFERENCES public.assets(id);


--
-- Name: events fk_rails_b2c25fd3b4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_b2c25fd3b4 FOREIGN KEY (actor_user_id) REFERENCES public.users(id);


--
-- Name: search_logs fk_rails_ce16f6ff96; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_logs
    ADD CONSTRAINT fk_rails_ce16f6ff96 FOREIGN KEY (token_id) REFERENCES public.tokens(id);


--
-- Name: links fk_rails_e8baf7f889; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.links
    ADD CONSTRAINT fk_rails_e8baf7f889 FOREIGN KEY (src_asset_id) REFERENCES public.assets(id);


--
-- Name: assets fk_rails_f30da9254e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT fk_rails_f30da9254e FOREIGN KEY (owner_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261031000001'),
('20261030160002'),
('20261030160001'),
('20261030150101'),
('20261030000002'),
('20261030000001'),
('20261028000003'),
('20261028000002'),
('20261028000001'),
('20261027000012'),
('20261027000011'),
('20261027000010'),
('20261027000009'),
('20261027000008'),
('20261027000007'),
('20261027000006'),
('20261027000005'),
('20261027000004'),
('20261027000003'),
('20261027000002'),
('20261027000001');

