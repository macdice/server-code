--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'SQL_ASCII';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: sfrost; Type: SCHEMA; Schema: -; Owner: sfrost
--

CREATE SCHEMA sfrost;


ALTER SCHEMA sfrost OWNER TO sfrost;

--
-- Name: plperl; Type: PROCEDURAL LANGUAGE; Schema: -; Owner: pgbuildfarm
--

CREATE OR REPLACE PROCEDURAL LANGUAGE plperl;


ALTER PROCEDURAL LANGUAGE plperl OWNER TO pgbuildfarm;

--
-- Name: plperlu; Type: PROCEDURAL LANGUAGE; Schema: -; Owner: pgbuildfarm
--

CREATE OR REPLACE PROCEDURAL LANGUAGE plperlu;


ALTER PROCEDURAL LANGUAGE plperlu OWNER TO pgbuildfarm;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: pageinspect; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS pageinspect WITH SCHEMA public;


--
-- Name: EXTENSION pageinspect; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pageinspect IS 'inspect the contents of database pages at a low level';


--
-- Name: pg_freespacemap; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS pg_freespacemap WITH SCHEMA public;


--
-- Name: EXTENSION pg_freespacemap; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_freespacemap IS 'examine the free space map (FSM)';


SET search_path = public, pg_catalog;

--
-- Name: pending; Type: TYPE; Schema: public; Owner: pgbuildfarm
--

CREATE TYPE pending AS (
	name text,
	operating_system text,
	os_version text,
	compiler text,
	compiler_version text,
	architecture text,
	owner_email text,
	owner text,
	status_ts timestamp without time zone
);


ALTER TYPE pending OWNER TO pgbuildfarm;

SET default_tablespace = '';

SET default_with_oids = true;

--
-- Name: build_status; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE build_status (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    status integer,
    stage text,
    log text,
    conf_sum text,
    branch text,
    changed_this_run text,
    changed_since_success text,
    log_archive bytea,
    log_archive_filenames text[],
    build_flags text[],
    report_time timestamp with time zone DEFAULT ('now'::text)::timestamp(6) with time zone,
    scm text,
    scmurl text,
    frozen_conf bytea,
    git_head_ref text
);


ALTER TABLE build_status OWNER TO pgbuildfarm;

--
-- Name: buildsystems; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE buildsystems (
    name text NOT NULL,
    secret text NOT NULL,
    operating_system text NOT NULL,
    os_version text NOT NULL,
    compiler text NOT NULL,
    compiler_version text NOT NULL,
    architecture text NOT NULL,
    status text NOT NULL,
    sys_owner text NOT NULL,
    owner_email text NOT NULL,
    status_ts timestamp without time zone DEFAULT (('now'::text)::timestamp(6) with time zone)::timestamp without time zone,
    no_alerts boolean DEFAULT false,
    sys_notes text,
    sys_notes_ts timestamp with time zone
);


ALTER TABLE buildsystems OWNER TO pgbuildfarm;

--
-- Name: personality; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE personality (
    name text NOT NULL,
    os_version text NOT NULL,
    compiler_version text NOT NULL,
    effective_date timestamp with time zone DEFAULT ('now'::text)::timestamp(6) with time zone NOT NULL
);


ALTER TABLE personality OWNER TO pgbuildfarm;

--
-- Name: allhist_summary; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW allhist_summary AS
 SELECT b.sysname,
    b.snapshot,
    b.status,
    b.stage,
    b.branch,
        CASE
            WHEN ((b.conf_sum ~ 'use_vpath'::text) AND (b.conf_sum !~ '''use_vpath'' => undef'::text)) THEN (b.build_flags || 'vpath'::text)
            ELSE b.build_flags
        END AS build_flags,
    s.operating_system,
    COALESCE(b.os_version, s.os_version) AS os_version,
    s.compiler,
    COALESCE(b.compiler_version, s.compiler_version) AS compiler_version,
    s.architecture,
    s.sys_notes_ts,
    s.sys_notes
   FROM buildsystems s,
    ( SELECT DISTINCT ON (bs.sysname, bs.branch, bs.report_time) bs.sysname,
            bs.snapshot,
            bs.status,
            bs.stage,
            bs.branch,
            bs.build_flags,
            bs.conf_sum,
            bs.report_time,
            p.compiler_version,
            p.os_version
           FROM (build_status bs
             LEFT JOIN personality p ON (((p.name = bs.sysname) AND (p.effective_date <= bs.report_time))))
          ORDER BY bs.sysname, bs.branch, bs.report_time, (p.effective_date IS NULL), p.effective_date DESC) b
  WHERE ((s.name = b.sysname) AND (s.status = 'approved'::text));


ALTER TABLE allhist_summary OWNER TO pgbuildfarm;

--
-- Name: allhist_summary(timestamp without time zone); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION allhist_summary(ts timestamp without time zone) RETURNS SETOF allhist_summary
    LANGUAGE sql
    AS $_$

 SELECT b.sysname, b.snapshot, b.status, b.stage, b.branch, 
        CASE
            WHEN b.conf_sum ~ 'use_vpath'::text AND b.conf_sum !~ '''use_vpath'' => undef'::text THEN b.build_flags || 'vpath'::text
            ELSE b.build_flags
        END AS build_flags, s.operating_system, COALESCE(b.os_version, s.os_version) AS os_version, s.compiler, COALESCE(b.compiler_version, s.compiler_version) AS compiler_version, s.architecture, s.sys_notes_ts, s.sys_notes
   FROM buildsystems s, ( SELECT DISTINCT ON (bs.sysname, bs.branch, bs.report_time) bs.sysname, bs.snapshot, bs.status, bs.stage, bs.branch, bs.build_flags, bs.conf_sum, bs.report_time, p.compiler_version, p.os_version
           FROM build_status bs
      LEFT JOIN personality p ON p.name = bs.sysname AND p.effective_date <= bs.report_time
      WHERE bs.snapshot > $1
     ORDER BY bs.sysname, bs.branch, bs.report_time, p.effective_date IS NULL, p.effective_date DESC) b
  WHERE s.name = b.sysname AND s.status = 'approved'::text


$_$;


ALTER FUNCTION public.allhist_summary(ts timestamp without time zone) OWNER TO pgbuildfarm;

--
-- Name: approve(text, text); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION approve(text, text) RETURNS text
    LANGUAGE sql
    AS $_$ update buildsystems set name = $2, status = 'approved' where name = $1 and status = 'pending'; select owner_email || ':' || name || ':' || secret from buildsystems where name = $2;$_$;


ALTER FUNCTION public.approve(text, text) OWNER TO pgbuildfarm;

--
-- Name: pending(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION pending() RETURNS SETOF pending
    LANGUAGE sql
    AS $$select name,operating_system,os_version,compiler,compiler_version,architecture,owner_email, sys_owner, status_ts from buildsystems where status = 'pending' order by status_ts $$;


ALTER FUNCTION public.pending() OWNER TO pgbuildfarm;

--
-- Name: plperl_call_handler(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION plperl_call_handler() RETURNS language_handler
    LANGUAGE c
    AS '$libdir/plperl', 'plperl_call_handler';


ALTER FUNCTION public.plperl_call_handler() OWNER TO pgbuildfarm;

--
-- Name: plpgsql_call_handler(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION plpgsql_call_handler() RETURNS language_handler
    LANGUAGE c
    AS '$libdir/plpgsql', 'plpgsql_call_handler';


ALTER FUNCTION public.plpgsql_call_handler() OWNER TO pgbuildfarm;

--
-- Name: purge_build_status_recent_500(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION purge_build_status_recent_500() RETURNS void
    LANGUAGE plpgsql
    AS $$ begin delete from build_status_recent_500 b using (with x as (select sysname, snapshot, rank() over (partition by sysname, branch order by snapshot desc) as rank from build_status_recent_500) select * from x where rank > 500) o where o.sysname = b.sysname and o.snapshot = b.snapshot; end; $$;


ALTER FUNCTION public.purge_build_status_recent_500() OWNER TO pgbuildfarm;

--
-- Name: script_version(text); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION script_version(text) RETURNS text
    LANGUAGE plperl
    AS $_$

   my $log = shift;
   if ($log =~ /'script_version' => '(REL_)?(\d+)(\.(\d+))?[.']/)
   {
	return sprintf("%0.3d%0.3d",$2,$4);
   }
   return '-1';

$_$;


ALTER FUNCTION public.script_version(text) OWNER TO pgbuildfarm;

--
-- Name: set_build_status_recent_500(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION set_build_status_recent_500() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ begin insert into build_status_recent_500 (sysname, snapshot, status, stage, branch) values (new.sysname, new.snapshot, new.status, new.stage, new.branch); return new; end; $$;


ALTER FUNCTION public.set_build_status_recent_500() OWNER TO pgbuildfarm;

--
-- Name: set_latest(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION set_latest() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

	begin
		update latest_snapshot 
			set snapshot = 
	(case when snapshot > NEW.snapshot then snapshot else NEW.snapshot end)
			where sysname = NEW.sysname and
				branch = NEW.branch;
		if not found then
			insert into latest_snapshot
				values(NEW.sysname, NEW.branch, NEW.snapshot);
		end if;
		return NEW;
	end;
$$;


ALTER FUNCTION public.set_latest() OWNER TO pgbuildfarm;

--
-- Name: set_local_error_terse(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION set_local_error_terse() RETURNS void
    LANGUAGE sql SECURITY DEFINER
    AS $$ set local log_error_verbosity = terse $$;


ALTER FUNCTION public.set_local_error_terse() OWNER TO postgres;

--
-- Name: web_script_version(text); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION web_script_version(text) RETURNS text
    LANGUAGE plperl
    AS $_$

   my $log = shift;
   if ($log =~ /'web_script_version' => '(REL_)?(\d+)(\.(\d+))?[.']/)
   {
	return sprintf("%0.3d%0.3d",$2,$4);
   }
   return '-1';

$_$;


ALTER FUNCTION public.web_script_version(text) OWNER TO pgbuildfarm;

SET default_with_oids = false;

--
-- Name: alerts; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE alerts (
    sysname text NOT NULL,
    branch text NOT NULL,
    first_alert timestamp without time zone,
    last_notification timestamp without time zone
);


ALTER TABLE alerts OWNER TO pgbuildfarm;

--
-- Name: build_status_export; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW build_status_export AS
 SELECT build_status.sysname AS name,
    build_status.snapshot,
    build_status.stage,
    build_status.branch,
    build_status.build_flags
   FROM build_status;


ALTER TABLE build_status_export OWNER TO pgbuildfarm;

SET default_with_oids = true;

--
-- Name: build_status_log; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE build_status_log (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text text,
    stage_duration interval
);


ALTER TABLE build_status_log OWNER TO pgbuildfarm;

SET default_with_oids = false;

--
-- Name: build_status_recent_500; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE build_status_recent_500 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    status integer,
    stage text,
    branch text,
    report_time timestamp with time zone DEFAULT ('now'::text)::timestamp(6) with time zone
);


ALTER TABLE build_status_recent_500 OWNER TO pgbuildfarm;

--
-- Name: buildsystems_export; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW buildsystems_export AS
 SELECT buildsystems.name,
    buildsystems.operating_system,
    buildsystems.os_version,
    buildsystems.compiler,
    buildsystems.compiler_version,
    buildsystems.architecture
   FROM buildsystems
  WHERE (buildsystems.status = 'approved'::text);


ALTER TABLE buildsystems_export OWNER TO pgbuildfarm;

SET default_with_oids = true;

--
-- Name: dashboard_mat; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE dashboard_mat (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    status integer,
    stage text,
    branch text NOT NULL,
    build_flags text[],
    operating_system text,
    os_version text,
    compiler text,
    compiler_version text,
    architecture text,
    sys_notes_ts timestamp with time zone,
    sys_notes text,
    git_head_ref text
);


ALTER TABLE dashboard_mat OWNER TO pgbuildfarm;

--
-- Name: latest_snapshot; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE latest_snapshot (
    sysname text NOT NULL,
    branch text NOT NULL,
    snapshot timestamp without time zone NOT NULL
);


ALTER TABLE latest_snapshot OWNER TO pgbuildfarm;

--
-- Name: dashboard_mat_data; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW dashboard_mat_data AS
 SELECT b.sysname,
    b.snapshot,
    b.status,
    b.stage,
    b.branch,
        CASE
            WHEN ((b.conf_sum ~ 'use_vpath'::text) AND (b.conf_sum !~ '''use_vpath'' => undef'::text)) THEN (b.build_flags || 'vpath'::text)
            ELSE b.build_flags
        END AS build_flags,
    s.operating_system,
    COALESCE(b.os_version, s.os_version) AS os_version,
    s.compiler,
    COALESCE(b.compiler_version, s.compiler_version) AS compiler_version,
    s.architecture,
    s.sys_notes_ts,
    s.sys_notes,
    b.git_head_ref
   FROM buildsystems s,
    ( SELECT DISTINCT ON (bs.sysname, bs.branch, bs.report_time) bs.sysname,
            bs.snapshot,
            bs.status,
            bs.stage,
            bs.branch,
            bs.build_flags,
            bs.conf_sum,
            bs.report_time,
            bs.git_head_ref,
            p.compiler_version,
            p.os_version
           FROM ((build_status bs
             JOIN latest_snapshot m USING (sysname, snapshot, branch))
             LEFT JOIN personality p ON (((p.name = bs.sysname) AND (p.effective_date <= bs.report_time))))
          WHERE (m.snapshot > (now() - '30 days'::interval))
          ORDER BY bs.sysname, bs.branch, bs.report_time, (p.effective_date IS NULL), p.effective_date DESC) b
  WHERE ((s.name = b.sysname) AND (s.status = 'approved'::text));


ALTER TABLE dashboard_mat_data OWNER TO pgbuildfarm;

--
-- Name: failures; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW failures AS
 SELECT build_status.sysname,
    build_status.snapshot,
    build_status.stage,
    build_status.conf_sum,
    build_status.branch,
    build_status.changed_this_run,
    build_status.changed_since_success,
    build_status.log_archive_filenames,
    build_status.build_flags,
    build_status.report_time
   FROM build_status
  WHERE (((build_status.stage <> 'OK'::text) AND (build_status.stage !~~ 'CVS%'::text)) AND (build_status.report_time IS NOT NULL));


ALTER TABLE failures OWNER TO pgbuildfarm;

SET default_with_oids = false;

--
-- Name: nrecent_failures; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE nrecent_failures (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text
);


ALTER TABLE nrecent_failures OWNER TO pgbuildfarm;

--
-- Name: long_term_fails; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW long_term_fails AS
 WITH max_fail AS (
         SELECT nrecent_failures.sysname,
            nrecent_failures.branch,
            max(nrecent_failures.snapshot) AS snapshot
           FROM nrecent_failures
          WHERE (nrecent_failures.snapshot > (now() - '7 days'::interval))
          GROUP BY nrecent_failures.sysname, nrecent_failures.branch
        ), still_failing AS (
         SELECT m.sysname,
            m.branch,
            m.snapshot
           FROM max_fail m
          WHERE (NOT (EXISTS ( SELECT 1
                   FROM dashboard_mat d
                  WHERE (((d.sysname = m.sysname) AND (d.branch = m.branch)) AND (d.stage = 'OK'::text)))))
        ), last_success AS (
         SELECT r.sysname,
            r.branch,
            max(r.snapshot) AS last_success
           FROM build_status_recent_500 r
          WHERE ((EXISTS ( SELECT 1
                   FROM still_failing s
                  WHERE ((r.sysname = s.sysname) AND (r.branch = s.branch)))) AND (r.stage = 'OK'::text))
          GROUP BY r.sysname, r.branch
        )
 SELECT bs.sys_owner,
    bs.owner_email,
    sf.sysname,
    sf.branch,
    sf.snapshot,
    age(l.last_success) AS age_since_last_success
   FROM ((still_failing sf
     JOIN buildsystems bs ON ((bs.name = sf.sysname)))
     LEFT JOIN last_success l ON (((l.sysname = sf.sysname) AND (l.branch = sf.branch))))
  WHERE ((l.last_success IS NULL) OR (l.last_success < (now() - '14 days'::interval)))
  ORDER BY sf.sysname, sf.branch;


ALTER TABLE long_term_fails OWNER TO pgbuildfarm;

--
-- Name: nrecent_failures_db_data; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW nrecent_failures_db_data AS
 SELECT b.sysname,
    b.snapshot,
    b.status,
    b.stage,
    b.branch,
        CASE
            WHEN ((b.conf_sum ~ 'use_vpath'::text) AND (b.conf_sum !~ '''use_vpath'' => undef'::text)) THEN (b.build_flags || 'vpath'::text)
            ELSE b.build_flags
        END AS build_flags,
    s.operating_system,
    COALESCE(b.os_version, s.os_version) AS os_version,
    s.compiler,
    COALESCE(b.compiler_version, s.compiler_version) AS compiler_version,
    s.architecture,
    s.sys_notes_ts,
    s.sys_notes
   FROM buildsystems s,
    ( SELECT DISTINCT ON (bs.sysname, bs.branch, bs.report_time) bs.sysname,
            bs.snapshot,
            bs.status,
            bs.stage,
            bs.branch,
            bs.build_flags,
            bs.conf_sum,
            bs.report_time,
            p.compiler_version,
            p.os_version
           FROM ((build_status bs
             JOIN nrecent_failures m USING (sysname, snapshot, branch))
             LEFT JOIN personality p ON (((p.name = bs.sysname) AND (p.effective_date <= bs.report_time))))
          WHERE (m.snapshot > (now() - '90 days'::interval))
          ORDER BY bs.sysname, bs.branch, bs.report_time, (p.effective_date IS NULL), p.effective_date DESC) b
  WHERE ((s.name = b.sysname) AND (s.status = 'approved'::text));


ALTER TABLE nrecent_failures_db_data OWNER TO pgbuildfarm;

--
-- Name: recent_failures; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW recent_failures AS
 SELECT build_status.sysname,
    build_status.snapshot,
    build_status.stage,
    build_status.conf_sum,
    build_status.branch,
    build_status.changed_this_run,
    build_status.changed_since_success,
    build_status.log_archive_filenames,
    build_status.build_flags,
    build_status.report_time,
    build_status.log
   FROM build_status
  WHERE ((((build_status.stage <> 'OK'::text) AND (build_status.stage !~~ 'CVS%'::text)) AND (build_status.report_time IS NOT NULL)) AND ((build_status.snapshot + '3 mons'::interval) > ('now'::text)::timestamp(6) with time zone));


ALTER TABLE recent_failures OWNER TO pgbuildfarm;

--
-- Name: script_versions; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW script_versions AS
 SELECT b.sysname,
    b.snapshot,
    b.branch,
    (script_version(b.conf_sum))::numeric AS script_version,
    (web_script_version(b.conf_sum))::numeric AS web_script_version
   FROM (build_status b
     JOIN dashboard_mat d ON (((b.sysname = d.sysname) AND (b.snapshot = d.snapshot))));


ALTER TABLE script_versions OWNER TO pgbuildfarm;

--
-- Name: script_versions2; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW script_versions2 AS
 SELECT b.sysname,
    b.snapshot,
    b.branch,
    script_version(b.conf_sum) AS script_version,
    web_script_version(b.conf_sum) AS web_script_version
   FROM (build_status b
     JOIN dashboard_mat d ON (((b.sysname = d.sysname) AND (b.snapshot = d.snapshot))));


ALTER TABLE script_versions2 OWNER TO pgbuildfarm;

--
-- Name: alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY alerts
    ADD CONSTRAINT alerts_pkey PRIMARY KEY (sysname, branch);


--
-- Name: build_status_log_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY build_status_log
    ADD CONSTRAINT build_status_log_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY build_status
    ADD CONSTRAINT build_status_pkey PRIMARY KEY (sysname, snapshot);


--
-- Name: build_status_recent_500_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY build_status_recent_500
    ADD CONSTRAINT build_status_recent_500_pkey PRIMARY KEY (sysname, snapshot);


--
-- Name: buildsystems_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY buildsystems
    ADD CONSTRAINT buildsystems_pkey PRIMARY KEY (name);


--
-- Name: dashboard_mat_pk; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY dashboard_mat
    ADD CONSTRAINT dashboard_mat_pk PRIMARY KEY (branch, sysname, snapshot);

ALTER TABLE dashboard_mat CLUSTER ON dashboard_mat_pk;


--
-- Name: latest_snapshot_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY latest_snapshot
    ADD CONSTRAINT latest_snapshot_pkey PRIMARY KEY (sysname, branch);


--
-- Name: nrecent_failures_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY nrecent_failures
    ADD CONSTRAINT nrecent_failures_pkey PRIMARY KEY (sysname, snapshot);


--
-- Name: personality_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY personality
    ADD CONSTRAINT personality_pkey PRIMARY KEY (name, effective_date);


--
-- Name: bs_branch_snapshot_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX bs_branch_snapshot_idx ON build_status USING btree (branch, snapshot);


--
-- Name: bs_status_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX bs_status_idx ON buildsystems USING btree (status);


--
-- Name: bs_sysname_branch_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX bs_sysname_branch_idx ON build_status USING btree (sysname, branch);


--
-- Name: bs_sysname_branch_report_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX bs_sysname_branch_report_idx ON build_status USING btree (sysname, branch, report_time);


--
-- Name: bs_sysname_branch_snap_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX bs_sysname_branch_snap_idx ON build_status USING btree (sysname, branch, snapshot DESC);


--
-- Name: bsr500_branch_snapshot_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX bsr500_branch_snapshot_idx ON build_status_recent_500 USING btree (branch, snapshot);


--
-- Name: bsr500_sysname_branch_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX bsr500_sysname_branch_idx ON build_status_recent_500 USING btree (sysname, branch);


--
-- Name: bsr500_sysname_branch_report_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX bsr500_sysname_branch_report_idx ON build_status_recent_500 USING btree (sysname, branch, report_time);


--
-- Name: bsr500_sysname_branch_snap_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX bsr500_sysname_branch_snap_idx ON build_status_recent_500 USING btree (sysname, branch, snapshot DESC);


--
-- Name: build_status_log_snapshot_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX build_status_log_snapshot_idx ON build_status_log USING btree (snapshot);


--
-- Name: build_status_log_stage_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX build_status_log_stage_idx ON build_status_log USING btree (log_stage);


--
-- Name: set_build_status_recent_500; Type: TRIGGER; Schema: public; Owner: pgbuildfarm
--

CREATE TRIGGER set_build_status_recent_500 AFTER INSERT ON build_status FOR EACH ROW EXECUTE PROCEDURE set_build_status_recent_500();


--
-- Name: set_latest_snapshot; Type: TRIGGER; Schema: public; Owner: pgbuildfarm
--

CREATE TRIGGER set_latest_snapshot AFTER INSERT ON build_status FOR EACH ROW EXECUTE PROCEDURE set_latest();


--
-- Name: bs_fk; Type: FK CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status
    ADD CONSTRAINT bs_fk FOREIGN KEY (sysname) REFERENCES buildsystems(name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: build_status_log_sysname_fkey; Type: FK CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log
    ADD CONSTRAINT build_status_log_sysname_fkey FOREIGN KEY (sysname, snapshot) REFERENCES build_status(sysname, snapshot) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: personality_build_systems_name_fk; Type: FK CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY personality
    ADD CONSTRAINT personality_build_systems_name_fk FOREIGN KEY (name) REFERENCES buildsystems(name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO pgbuildfarm;
GRANT USAGE ON SCHEMA public TO PUBLIC;


--
-- Name: build_status; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE build_status FROM PUBLIC;
REVOKE ALL ON TABLE build_status FROM pgbuildfarm;
GRANT ALL ON TABLE build_status TO pgbuildfarm;
GRANT SELECT,INSERT ON TABLE build_status TO pgbfweb;
GRANT SELECT ON TABLE build_status TO rssfeed;
GRANT SELECT ON TABLE build_status TO reader;


--
-- Name: buildsystems; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE buildsystems FROM PUBLIC;
REVOKE ALL ON TABLE buildsystems FROM pgbuildfarm;
GRANT ALL ON TABLE buildsystems TO pgbuildfarm;
GRANT SELECT,INSERT,UPDATE ON TABLE buildsystems TO pgbfweb;
GRANT SELECT ON TABLE buildsystems TO rssfeed;
GRANT SELECT ON TABLE buildsystems TO reader;


--
-- Name: personality; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE personality FROM PUBLIC;
REVOKE ALL ON TABLE personality FROM pgbuildfarm;
GRANT ALL ON TABLE personality TO pgbuildfarm;
GRANT SELECT,INSERT ON TABLE personality TO pgbfweb;
GRANT SELECT ON TABLE personality TO rssfeed;
GRANT SELECT ON TABLE personality TO reader;


--
-- Name: allhist_summary; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE allhist_summary FROM PUBLIC;
REVOKE ALL ON TABLE allhist_summary FROM pgbuildfarm;
GRANT ALL ON TABLE allhist_summary TO pgbuildfarm;
GRANT SELECT ON TABLE allhist_summary TO rssfeed;
GRANT SELECT ON TABLE allhist_summary TO reader;


--
-- Name: alerts; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE alerts FROM PUBLIC;
REVOKE ALL ON TABLE alerts FROM pgbuildfarm;
GRANT ALL ON TABLE alerts TO pgbuildfarm;
GRANT SELECT ON TABLE alerts TO reader;


--
-- Name: build_status_export; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE build_status_export FROM PUBLIC;
REVOKE ALL ON TABLE build_status_export FROM pgbuildfarm;
GRANT ALL ON TABLE build_status_export TO pgbuildfarm;
GRANT SELECT ON TABLE build_status_export TO reader;


--
-- Name: build_status_log; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE build_status_log FROM PUBLIC;
REVOKE ALL ON TABLE build_status_log FROM pgbuildfarm;
GRANT ALL ON TABLE build_status_log TO pgbuildfarm;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE build_status_log TO pgbfweb;
GRANT SELECT ON TABLE build_status_log TO rssfeed;
GRANT SELECT ON TABLE build_status_log TO reader;


--
-- Name: build_status_recent_500; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE build_status_recent_500 FROM PUBLIC;
REVOKE ALL ON TABLE build_status_recent_500 FROM pgbuildfarm;
GRANT ALL ON TABLE build_status_recent_500 TO pgbuildfarm;
GRANT SELECT,INSERT ON TABLE build_status_recent_500 TO pgbfweb;
GRANT SELECT ON TABLE build_status_recent_500 TO reader;


--
-- Name: buildsystems_export; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE buildsystems_export FROM PUBLIC;
REVOKE ALL ON TABLE buildsystems_export FROM pgbuildfarm;
GRANT ALL ON TABLE buildsystems_export TO pgbuildfarm;
GRANT SELECT ON TABLE buildsystems_export TO reader;


--
-- Name: dashboard_mat; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE dashboard_mat FROM PUBLIC;
REVOKE ALL ON TABLE dashboard_mat FROM pgbuildfarm;
GRANT ALL ON TABLE dashboard_mat TO pgbuildfarm;
GRANT SELECT,INSERT,DELETE ON TABLE dashboard_mat TO pgbfweb;
GRANT SELECT ON TABLE dashboard_mat TO reader;


--
-- Name: latest_snapshot; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE latest_snapshot FROM PUBLIC;
REVOKE ALL ON TABLE latest_snapshot FROM pgbuildfarm;
GRANT ALL ON TABLE latest_snapshot TO pgbuildfarm;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE latest_snapshot TO pgbfweb;
GRANT SELECT ON TABLE latest_snapshot TO reader;


--
-- Name: dashboard_mat_data; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE dashboard_mat_data FROM PUBLIC;
REVOKE ALL ON TABLE dashboard_mat_data FROM pgbuildfarm;
GRANT ALL ON TABLE dashboard_mat_data TO pgbuildfarm;
GRANT SELECT ON TABLE dashboard_mat_data TO pgbfweb;
GRANT SELECT ON TABLE dashboard_mat_data TO reader;


--
-- Name: failures; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE failures FROM PUBLIC;
REVOKE ALL ON TABLE failures FROM pgbuildfarm;
GRANT ALL ON TABLE failures TO pgbuildfarm;
GRANT SELECT ON TABLE failures TO reader;


--
-- Name: nrecent_failures; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE nrecent_failures FROM PUBLIC;
REVOKE ALL ON TABLE nrecent_failures FROM pgbuildfarm;
GRANT ALL ON TABLE nrecent_failures TO pgbuildfarm;
GRANT SELECT,INSERT,DELETE ON TABLE nrecent_failures TO pgbfweb;
GRANT SELECT ON TABLE nrecent_failures TO reader;


--
-- Name: long_term_fails; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE long_term_fails FROM PUBLIC;
REVOKE ALL ON TABLE long_term_fails FROM pgbuildfarm;
GRANT ALL ON TABLE long_term_fails TO pgbuildfarm;
GRANT SELECT ON TABLE long_term_fails TO reader;


--
-- Name: nrecent_failures_db_data; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE nrecent_failures_db_data FROM PUBLIC;
REVOKE ALL ON TABLE nrecent_failures_db_data FROM pgbuildfarm;
GRANT ALL ON TABLE nrecent_failures_db_data TO pgbuildfarm;
GRANT SELECT ON TABLE nrecent_failures_db_data TO pgbfweb;
GRANT SELECT ON TABLE nrecent_failures_db_data TO reader;


--
-- Name: recent_failures; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE recent_failures FROM PUBLIC;
REVOKE ALL ON TABLE recent_failures FROM pgbuildfarm;
GRANT ALL ON TABLE recent_failures TO pgbuildfarm;
GRANT SELECT ON TABLE recent_failures TO reader;


--
-- Name: script_versions; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE script_versions FROM PUBLIC;
REVOKE ALL ON TABLE script_versions FROM pgbuildfarm;
GRANT ALL ON TABLE script_versions TO pgbuildfarm;
GRANT SELECT ON TABLE script_versions TO reader;


--
-- Name: script_versions2; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE script_versions2 FROM PUBLIC;
REVOKE ALL ON TABLE script_versions2 FROM pgbuildfarm;
GRANT ALL ON TABLE script_versions2 TO pgbuildfarm;
GRANT SELECT ON TABLE script_versions2 TO reader;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: pgbuildfarm
--

ALTER DEFAULT PRIVILEGES FOR ROLE pgbuildfarm IN SCHEMA public REVOKE ALL ON TABLES  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE pgbuildfarm IN SCHEMA public REVOKE ALL ON TABLES  FROM pgbuildfarm;
ALTER DEFAULT PRIVILEGES FOR ROLE pgbuildfarm IN SCHEMA public GRANT SELECT ON TABLES  TO reader;


--
-- PostgreSQL database dump complete
--

