-- Baseline migration capturing the full schema already live on both
-- poll-social-app-dev and poll-social-app (prod) as of 2026-06-26, adopting
-- Supabase CLI migration tracking on a project that previously had none.
-- Marked as already-applied on both projects via `supabase migration repair
-- --status applied 20260626134252` (not run via db push) — do not edit this
-- file after that point. All future schema changes should be new files
-- created with `supabase migration new <name>`.

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."create_poll_analytics"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into poll_analytics (poll_id)
  values (new.id);

  return new;
end;
$$;


ALTER FUNCTION "public"."create_poll_analytics"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_comments_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  update poll_analytics
  set comments_count = greatest(comments_count - 1, 0),
      updated_at = now()
  where poll_id = old.poll_id;

  return old;
end;
$$;


ALTER FUNCTION "public"."decrement_comments_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_likes_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  update poll_analytics
  set likes_count = greatest(likes_count - 1, 0),
      updated_at = now()
  where poll_id = old.poll_id;

  return old;
end;
$$;


ALTER FUNCTION "public"."decrement_likes_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_votes_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  update poll_analytics
  set votes_count = greatest(votes_count - 1, 0),
      updated_at = now()
  where poll_id = old.poll_id;

  return old;
end;
$$;


ALTER FUNCTION "public"."decrement_votes_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_comments_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if new.status = 'active' then
    update poll_analytics
    set comments_count = comments_count + 1,
        updated_at = now()
    where poll_id = new.poll_id;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."increment_comments_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_likes_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  update poll_analytics
  set likes_count = likes_count + 1,
      updated_at = now()
  where poll_id = new.poll_id;

  return new;
end;
$$;


ALTER FUNCTION "public"."increment_likes_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_votes_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  update poll_analytics
  set votes_count = votes_count + 1,
      updated_at = now()
  where poll_id = new.poll_id;

  return new;
end;
$$;


ALTER FUNCTION "public"."increment_votes_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_hashtags"("search_text" "text") RETURNS TABLE("id" "uuid", "tag" "text")
    LANGUAGE "sql" STABLE
    AS $$
  select
    hashtags.id,
    hashtags.tag
  from hashtags
  where hashtags.tag ilike '%' || search_text || '%'
  order by hashtags.tag asc;
$$;


ALTER FUNCTION "public"."search_hashtags"("search_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_polls"("search_text" "text") RETURNS TABLE("id" "uuid", "question" "text", "description" "text", "user_id" "uuid", "username" "text", "avatar_url" "text", "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE
    AS $$
  select
    polls.id,
    polls.question,
    polls.description,
    polls.user_id,
    profiles.username,
    profiles.avatar_url,
    polls.created_at
  from polls
  join profiles on profiles.id = polls.user_id
  where polls.status = 'active'
    and polls.visibility = 'public'
    and (
      polls.question ilike '%' || search_text || '%'
      or polls.description ilike '%' || search_text || '%'
    )
  order by polls.created_at desc;
$$;


ALTER FUNCTION "public"."search_polls"("search_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_topics"("search_text" "text") RETURNS TABLE("id" "uuid", "name" "text", "slug" "text", "description" "text")
    LANGUAGE "sql" STABLE
    AS $$
  select
    topics.id,
    topics.name,
    topics.slug,
    topics.description
  from topics
  where topics.name ilike '%' || search_text || '%'
  order by topics.name asc;
$$;


ALTER FUNCTION "public"."search_topics"("search_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_users"("search_text" "text") RETURNS TABLE("id" "uuid", "username" "text", "display_name" "text", "avatar_url" "text", "bio" "text")
    LANGUAGE "sql" STABLE
    AS $$
  select
    profiles.id,
    profiles.username,
    profiles.display_name,
    profiles.avatar_url,
    profiles.bio
  from profiles
  where
    profiles.username ilike '%' || search_text || '%'
    or profiles.display_name ilike '%' || search_text || '%'
  order by profiles.username asc;
$$;


ALTER FUNCTION "public"."search_users"("search_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_poll_share_slug"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if new.visibility = 'public' and new.share_slug is null then
    new.share_slug := substr(replace(new.id::text, '-', ''), 1, 10);
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."set_poll_share_slug"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."blocks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "blocker_id" "uuid" NOT NULL,
    "blocked_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "blocks_check" CHECK (("blocker_id" <> "blocked_id"))
);


ALTER TABLE "public"."blocks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."comments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "poll_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "parent_comment_id" "uuid",
    "comment_text" "text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "comments_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'deleted'::"text", 'blocked'::"text"])))
);


ALTER TABLE "public"."comments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."follows" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "follower_id" "uuid" NOT NULL,
    "following_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "follows_check" CHECK (("follower_id" <> "following_id"))
);


ALTER TABLE "public"."follows" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."hashtags" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tag" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."hashtags" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."likes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "poll_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."likes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "title" "text" NOT NULL,
    "message" "text",
    "related_poll_id" "uuid",
    "related_user_id" "uuid",
    "is_read" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "notifications_type_check" CHECK (("type" = ANY (ARRAY['vote'::"text", 'like'::"text", 'comment'::"text", 'follow'::"text", 'system'::"text"])))
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."poll_analytics" (
    "poll_id" "uuid" NOT NULL,
    "views_count" integer DEFAULT 0,
    "votes_count" integer DEFAULT 0,
    "likes_count" integer DEFAULT 0,
    "comments_count" integer DEFAULT 0,
    "shares_count" integer DEFAULT 0,
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."poll_analytics" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."poll_hashtags" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "poll_id" "uuid" NOT NULL,
    "hashtag_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."poll_hashtags" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."poll_media" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "poll_id" "uuid" NOT NULL,
    "media_type" "text" NOT NULL,
    "media_url" "text" NOT NULL,
    "thumbnail_url" "text",
    "duration_seconds" integer,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "poll_media_media_type_check" CHECK (("media_type" = ANY (ARRAY['image'::"text", 'video'::"text"])))
);


ALTER TABLE "public"."poll_media" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."poll_options" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "poll_id" "uuid" NOT NULL,
    "option_text" "text" NOT NULL,
    "option_order" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."poll_options" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."poll_topics" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "poll_id" "uuid" NOT NULL,
    "topic_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."poll_topics" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."polls" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "question" "text" NOT NULL,
    "description" "text",
    "poll_type" "text" DEFAULT 'single_choice'::"text",
    "visibility" "text" DEFAULT 'public'::"text",
    "country" "text",
    "city" "text",
    "expires_at" timestamp with time zone,
    "status" "text" DEFAULT 'active'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "allow_embedding" boolean DEFAULT true NOT NULL,
    "share_slug" "text"
);


ALTER TABLE "public"."polls" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "username" "text" NOT NULL,
    "display_name" "text",
    "avatar_url" "text",
    "bio" "text",
    "country" "text",
    "city" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "reporter_id" "uuid" NOT NULL,
    "target_type" "text" NOT NULL,
    "target_id" "uuid" NOT NULL,
    "reason" "text" NOT NULL,
    "details" "text",
    "status" "text" DEFAULT 'pending'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "reports_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'reviewed'::"text", 'dismissed'::"text", 'action_taken'::"text"]))),
    CONSTRAINT "reports_target_type_check" CHECK (("target_type" = ANY (ARRAY['poll'::"text", 'comment'::"text", 'user'::"text"])))
);


ALTER TABLE "public"."reports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."topics" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."topics" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."trending_polls" AS
 SELECT "polls"."id",
    "polls"."user_id",
    "polls"."question",
    "polls"."description",
    "polls"."poll_type",
    "polls"."visibility",
    "polls"."country",
    "polls"."city",
    "polls"."expires_at",
    "polls"."status",
    "polls"."created_at",
    "profiles"."username",
    "profiles"."avatar_url",
    "poll_analytics"."votes_count",
    "poll_analytics"."likes_count",
    "poll_analytics"."comments_count",
    "poll_analytics"."shares_count",
    (((((("poll_analytics"."votes_count" * 3) + ("poll_analytics"."comments_count" * 2)) + ("poll_analytics"."likes_count" * 1)) + ("poll_analytics"."shares_count" * 4)))::numeric - ((EXTRACT(epoch FROM ("now"() - "polls"."created_at")) / (3600)::numeric) * 0.5)) AS "trending_score"
   FROM (("public"."polls"
     JOIN "public"."profiles" ON (("profiles"."id" = "polls"."user_id")))
     LEFT JOIN "public"."poll_analytics" ON (("poll_analytics"."poll_id" = "polls"."id")))
  WHERE (("polls"."status" = 'active'::"text") AND ("polls"."visibility" = 'public'::"text") AND (("polls"."expires_at" IS NULL) OR ("polls"."expires_at" > "now"())));


ALTER VIEW "public"."trending_polls" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."votes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "poll_id" "uuid" NOT NULL,
    "option_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."votes" OWNER TO "postgres";


ALTER TABLE ONLY "public"."blocks"
    ADD CONSTRAINT "blocks_blocker_id_blocked_id_key" UNIQUE ("blocker_id", "blocked_id");



ALTER TABLE ONLY "public"."blocks"
    ADD CONSTRAINT "blocks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."comments"
    ADD CONSTRAINT "comments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_follower_id_following_id_key" UNIQUE ("follower_id", "following_id");



ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hashtags"
    ADD CONSTRAINT "hashtags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hashtags"
    ADD CONSTRAINT "hashtags_tag_key" UNIQUE ("tag");



ALTER TABLE ONLY "public"."likes"
    ADD CONSTRAINT "likes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."likes"
    ADD CONSTRAINT "likes_poll_id_user_id_key" UNIQUE ("poll_id", "user_id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."poll_analytics"
    ADD CONSTRAINT "poll_analytics_pkey" PRIMARY KEY ("poll_id");



ALTER TABLE ONLY "public"."poll_hashtags"
    ADD CONSTRAINT "poll_hashtags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."poll_hashtags"
    ADD CONSTRAINT "poll_hashtags_poll_id_hashtag_id_key" UNIQUE ("poll_id", "hashtag_id");



ALTER TABLE ONLY "public"."poll_media"
    ADD CONSTRAINT "poll_media_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."poll_options"
    ADD CONSTRAINT "poll_options_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."poll_topics"
    ADD CONSTRAINT "poll_topics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."poll_topics"
    ADD CONSTRAINT "poll_topics_poll_id_topic_id_key" UNIQUE ("poll_id", "topic_id");



ALTER TABLE ONLY "public"."polls"
    ADD CONSTRAINT "polls_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_username_key" UNIQUE ("username");



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."topics"
    ADD CONSTRAINT "topics_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."topics"
    ADD CONSTRAINT "topics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."topics"
    ADD CONSTRAINT "topics_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."votes"
    ADD CONSTRAINT "votes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."votes"
    ADD CONSTRAINT "votes_poll_id_user_id_key" UNIQUE ("poll_id", "user_id");



CREATE INDEX "idx_comments_poll_id" ON "public"."comments" USING "btree" ("poll_id");



CREATE INDEX "idx_comments_user_id" ON "public"."comments" USING "btree" ("user_id");



CREATE INDEX "idx_follows_follower_id" ON "public"."follows" USING "btree" ("follower_id");



CREATE INDEX "idx_follows_following_id" ON "public"."follows" USING "btree" ("following_id");



CREATE INDEX "idx_hashtags_tag" ON "public"."hashtags" USING "btree" ("tag");



CREATE INDEX "idx_hashtags_tag_trgm" ON "public"."hashtags" USING "gin" ("tag" "public"."gin_trgm_ops");



CREATE INDEX "idx_likes_poll_id" ON "public"."likes" USING "btree" ("poll_id");



CREATE INDEX "idx_likes_user_id" ON "public"."likes" USING "btree" ("user_id");



CREATE INDEX "idx_notifications_is_read" ON "public"."notifications" USING "btree" ("is_read");



CREATE INDEX "idx_notifications_user_id" ON "public"."notifications" USING "btree" ("user_id");



CREATE INDEX "idx_poll_analytics_likes_count" ON "public"."poll_analytics" USING "btree" ("likes_count" DESC);



CREATE INDEX "idx_poll_analytics_votes_count" ON "public"."poll_analytics" USING "btree" ("votes_count" DESC);



CREATE INDEX "idx_poll_hashtags_hashtag_id" ON "public"."poll_hashtags" USING "btree" ("hashtag_id");



CREATE INDEX "idx_poll_hashtags_poll_id" ON "public"."poll_hashtags" USING "btree" ("poll_id");



CREATE INDEX "idx_poll_options_poll_id" ON "public"."poll_options" USING "btree" ("poll_id");



CREATE INDEX "idx_poll_topics_poll_id" ON "public"."poll_topics" USING "btree" ("poll_id");



CREATE INDEX "idx_poll_topics_topic_id" ON "public"."poll_topics" USING "btree" ("topic_id");



CREATE INDEX "idx_polls_country" ON "public"."polls" USING "btree" ("country");



CREATE INDEX "idx_polls_created_at" ON "public"."polls" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_polls_description_trgm" ON "public"."polls" USING "gin" ("description" "public"."gin_trgm_ops");



CREATE INDEX "idx_polls_question_trgm" ON "public"."polls" USING "gin" ("question" "public"."gin_trgm_ops");



CREATE INDEX "idx_polls_status" ON "public"."polls" USING "btree" ("status");



CREATE INDEX "idx_polls_user_id" ON "public"."polls" USING "btree" ("user_id");



CREATE UNIQUE INDEX "polls_share_slug_key" ON "public"."polls" USING "btree" ("share_slug");



CREATE INDEX "idx_profiles_display_name_trgm" ON "public"."profiles" USING "gin" ("display_name" "public"."gin_trgm_ops");



CREATE INDEX "idx_profiles_username_trgm" ON "public"."profiles" USING "gin" ("username" "public"."gin_trgm_ops");



CREATE INDEX "idx_reports_status" ON "public"."reports" USING "btree" ("status");



CREATE INDEX "idx_topics_name" ON "public"."topics" USING "btree" ("name");



CREATE INDEX "idx_topics_name_trgm" ON "public"."topics" USING "gin" ("name" "public"."gin_trgm_ops");



CREATE INDEX "idx_topics_slug" ON "public"."topics" USING "btree" ("slug");



CREATE INDEX "idx_votes_poll_id" ON "public"."votes" USING "btree" ("poll_id");



CREATE INDEX "idx_votes_user_id" ON "public"."votes" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "trg_create_poll_analytics" AFTER INSERT ON "public"."polls" FOR EACH ROW EXECUTE FUNCTION "public"."create_poll_analytics"();



CREATE OR REPLACE TRIGGER "polls_set_share_slug" BEFORE INSERT OR UPDATE ON "public"."polls" FOR EACH ROW EXECUTE FUNCTION "public"."set_poll_share_slug"();



CREATE OR REPLACE TRIGGER "trg_decrement_comments_count" AFTER DELETE ON "public"."comments" FOR EACH ROW EXECUTE FUNCTION "public"."decrement_comments_count"();



CREATE OR REPLACE TRIGGER "trg_decrement_likes_count" AFTER DELETE ON "public"."likes" FOR EACH ROW EXECUTE FUNCTION "public"."decrement_likes_count"();



CREATE OR REPLACE TRIGGER "trg_decrement_votes_count" AFTER DELETE ON "public"."votes" FOR EACH ROW EXECUTE FUNCTION "public"."decrement_votes_count"();



CREATE OR REPLACE TRIGGER "trg_increment_comments_count" AFTER INSERT ON "public"."comments" FOR EACH ROW EXECUTE FUNCTION "public"."increment_comments_count"();



CREATE OR REPLACE TRIGGER "trg_increment_likes_count" AFTER INSERT ON "public"."likes" FOR EACH ROW EXECUTE FUNCTION "public"."increment_likes_count"();



CREATE OR REPLACE TRIGGER "trg_increment_votes_count" AFTER INSERT ON "public"."votes" FOR EACH ROW EXECUTE FUNCTION "public"."increment_votes_count"();



ALTER TABLE ONLY "public"."blocks"
    ADD CONSTRAINT "blocks_blocked_id_fkey" FOREIGN KEY ("blocked_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."blocks"
    ADD CONSTRAINT "blocks_blocker_id_fkey" FOREIGN KEY ("blocker_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."comments"
    ADD CONSTRAINT "comments_parent_comment_id_fkey" FOREIGN KEY ("parent_comment_id") REFERENCES "public"."comments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."comments"
    ADD CONSTRAINT "comments_poll_id_fkey" FOREIGN KEY ("poll_id") REFERENCES "public"."polls"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."comments"
    ADD CONSTRAINT "comments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_follower_id_fkey" FOREIGN KEY ("follower_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_following_id_fkey" FOREIGN KEY ("following_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."likes"
    ADD CONSTRAINT "likes_poll_id_fkey" FOREIGN KEY ("poll_id") REFERENCES "public"."polls"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."likes"
    ADD CONSTRAINT "likes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_related_poll_id_fkey" FOREIGN KEY ("related_poll_id") REFERENCES "public"."polls"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_related_user_id_fkey" FOREIGN KEY ("related_user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."poll_analytics"
    ADD CONSTRAINT "poll_analytics_poll_id_fkey" FOREIGN KEY ("poll_id") REFERENCES "public"."polls"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."poll_hashtags"
    ADD CONSTRAINT "poll_hashtags_hashtag_id_fkey" FOREIGN KEY ("hashtag_id") REFERENCES "public"."hashtags"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."poll_hashtags"
    ADD CONSTRAINT "poll_hashtags_poll_id_fkey" FOREIGN KEY ("poll_id") REFERENCES "public"."polls"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."poll_media"
    ADD CONSTRAINT "poll_media_poll_id_fkey" FOREIGN KEY ("poll_id") REFERENCES "public"."polls"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."poll_options"
    ADD CONSTRAINT "poll_options_poll_id_fkey" FOREIGN KEY ("poll_id") REFERENCES "public"."polls"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."poll_topics"
    ADD CONSTRAINT "poll_topics_poll_id_fkey" FOREIGN KEY ("poll_id") REFERENCES "public"."polls"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."poll_topics"
    ADD CONSTRAINT "poll_topics_topic_id_fkey" FOREIGN KEY ("topic_id") REFERENCES "public"."topics"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."polls"
    ADD CONSTRAINT "polls_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."votes"
    ADD CONSTRAINT "votes_option_id_fkey" FOREIGN KEY ("option_id") REFERENCES "public"."poll_options"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."votes"
    ADD CONSTRAINT "votes_poll_id_fkey" FOREIGN KEY ("poll_id") REFERENCES "public"."polls"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."votes"
    ADD CONSTRAINT "votes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



CREATE POLICY "Active comments are viewable by everyone" ON "public"."comments" FOR SELECT USING (("status" = 'active'::"text"));



CREATE POLICY "Follows are viewable by everyone" ON "public"."follows" FOR SELECT USING (true);



CREATE POLICY "Hashtags are viewable by everyone" ON "public"."hashtags" FOR SELECT USING (true);



CREATE POLICY "Likes are viewable by everyone" ON "public"."likes" FOR SELECT USING (true);



CREATE POLICY "Poll analytics are viewable by everyone" ON "public"."poll_analytics" FOR SELECT USING (true);



CREATE POLICY "Poll hashtags are viewable by everyone" ON "public"."poll_hashtags" FOR SELECT USING (true);



CREATE POLICY "Poll media is viewable by everyone" ON "public"."poll_media" FOR SELECT USING (true);



CREATE POLICY "Poll options are viewable by everyone" ON "public"."poll_options" FOR SELECT USING (true);



CREATE POLICY "Poll topics are viewable by everyone" ON "public"."poll_topics" FOR SELECT USING (true);



CREATE POLICY "Profiles are viewable by everyone" ON "public"."profiles" FOR SELECT USING (true);



CREATE POLICY "Public polls are viewable by everyone" ON "public"."polls" FOR SELECT USING ((("visibility" = 'public'::"text") AND ("status" = 'active'::"text")));

CREATE POLICY "Users can view all their own polls" ON "public"."polls"
FOR SELECT TO "authenticated"
USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Topics are viewable by everyone" ON "public"."topics" FOR SELECT USING (true);



CREATE POLICY "Users can add hashtags to their own polls" ON "public"."poll_hashtags" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."polls"
  WHERE (("polls"."id" = "poll_hashtags"."poll_id") AND ("polls"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can add media to their own polls" ON "public"."poll_media" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."polls"
  WHERE (("polls"."id" = "poll_media"."poll_id") AND ("polls"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can add topics to their own polls" ON "public"."poll_topics" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."polls"
  WHERE (("polls"."id" = "poll_topics"."poll_id") AND ("polls"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can block as themselves" ON "public"."blocks" FOR INSERT WITH CHECK (("auth"."uid"() = "blocker_id"));



CREATE POLICY "Users can create comments as themselves" ON "public"."comments" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create options for their own polls" ON "public"."poll_options" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."polls"
  WHERE (("polls"."id" = "poll_options"."poll_id") AND ("polls"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can create reports as themselves" ON "public"."reports" FOR INSERT WITH CHECK (("auth"."uid"() = "reporter_id"));



CREATE POLICY "Users can create their own polls" ON "public"."polls" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete media from their own polls" ON "public"."poll_media" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."polls"
  WHERE (("polls"."id" = "poll_media"."poll_id") AND ("polls"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can delete their own comments" ON "public"."comments" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own polls" ON "public"."polls" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can follow as themselves" ON "public"."follows" FOR INSERT WITH CHECK (("auth"."uid"() = "follower_id"));



CREATE POLICY "Users can insert their own profile" ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can like as themselves" ON "public"."likes" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can unblock as themselves" ON "public"."blocks" FOR DELETE USING (("auth"."uid"() = "blocker_id"));



CREATE POLICY "Users can unfollow as themselves" ON "public"."follows" FOR DELETE USING (("auth"."uid"() = "follower_id"));



CREATE POLICY "Users can unlike their own likes" ON "public"."likes" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own comments" ON "public"."comments" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own notifications" ON "public"."notifications" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own polls" ON "public"."polls" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can view their own blocks" ON "public"."blocks" FOR SELECT USING (("auth"."uid"() = "blocker_id"));



CREATE POLICY "Users can view their own notifications" ON "public"."notifications" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own reports" ON "public"."reports" FOR SELECT USING (("auth"."uid"() = "reporter_id"));



CREATE POLICY "Users can vote as themselves" ON "public"."votes" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Votes are viewable by everyone" ON "public"."votes" FOR SELECT USING (true);



ALTER TABLE "public"."blocks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."comments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."follows" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."hashtags" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."likes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."poll_analytics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."poll_hashtags" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."poll_media" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."poll_options" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."poll_topics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."polls" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."topics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."votes" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."create_poll_analytics"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_poll_analytics"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_poll_analytics"() TO "service_role";



GRANT ALL ON FUNCTION "public"."decrement_comments_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_comments_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_comments_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."decrement_likes_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_likes_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_likes_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."decrement_votes_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_votes_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_votes_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_comments_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."increment_comments_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_comments_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_likes_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."increment_likes_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_likes_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_votes_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."increment_votes_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_votes_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."search_hashtags"("search_text" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."search_hashtags"("search_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_hashtags"("search_text" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."search_polls"("search_text" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."search_polls"("search_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_polls"("search_text" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."search_topics"("search_text" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."search_topics"("search_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_topics"("search_text" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."search_users"("search_text" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."search_users"("search_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_users"("search_text" "text") TO "service_role";



GRANT ALL ON TABLE "public"."blocks" TO "anon";
GRANT ALL ON TABLE "public"."blocks" TO "authenticated";
GRANT ALL ON TABLE "public"."blocks" TO "service_role";



GRANT ALL ON TABLE "public"."comments" TO "anon";
GRANT ALL ON TABLE "public"."comments" TO "authenticated";
GRANT ALL ON TABLE "public"."comments" TO "service_role";



GRANT ALL ON TABLE "public"."follows" TO "anon";
GRANT ALL ON TABLE "public"."follows" TO "authenticated";
GRANT ALL ON TABLE "public"."follows" TO "service_role";



GRANT ALL ON TABLE "public"."hashtags" TO "anon";
GRANT ALL ON TABLE "public"."hashtags" TO "authenticated";
GRANT ALL ON TABLE "public"."hashtags" TO "service_role";



GRANT ALL ON TABLE "public"."likes" TO "anon";
GRANT ALL ON TABLE "public"."likes" TO "authenticated";
GRANT ALL ON TABLE "public"."likes" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."poll_analytics" TO "anon";
GRANT ALL ON TABLE "public"."poll_analytics" TO "authenticated";
GRANT ALL ON TABLE "public"."poll_analytics" TO "service_role";



GRANT ALL ON TABLE "public"."poll_hashtags" TO "anon";
GRANT ALL ON TABLE "public"."poll_hashtags" TO "authenticated";
GRANT ALL ON TABLE "public"."poll_hashtags" TO "service_role";



GRANT ALL ON TABLE "public"."poll_media" TO "anon";
GRANT ALL ON TABLE "public"."poll_media" TO "authenticated";
GRANT ALL ON TABLE "public"."poll_media" TO "service_role";



GRANT ALL ON TABLE "public"."poll_options" TO "anon";
GRANT ALL ON TABLE "public"."poll_options" TO "authenticated";
GRANT ALL ON TABLE "public"."poll_options" TO "service_role";



GRANT ALL ON TABLE "public"."poll_topics" TO "anon";
GRANT ALL ON TABLE "public"."poll_topics" TO "authenticated";
GRANT ALL ON TABLE "public"."poll_topics" TO "service_role";



GRANT ALL ON TABLE "public"."polls" TO "anon";
GRANT ALL ON TABLE "public"."polls" TO "authenticated";
GRANT ALL ON TABLE "public"."polls" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."reports" TO "anon";
GRANT ALL ON TABLE "public"."reports" TO "authenticated";
GRANT ALL ON TABLE "public"."reports" TO "service_role";



GRANT ALL ON TABLE "public"."topics" TO "anon";
GRANT ALL ON TABLE "public"."topics" TO "authenticated";
GRANT ALL ON TABLE "public"."topics" TO "service_role";



GRANT ALL ON TABLE "public"."trending_polls" TO "anon";
GRANT ALL ON TABLE "public"."trending_polls" TO "authenticated";
GRANT ALL ON TABLE "public"."trending_polls" TO "service_role";



GRANT ALL ON TABLE "public"."votes" TO "anon";
GRANT ALL ON TABLE "public"."votes" TO "authenticated";
GRANT ALL ON TABLE "public"."votes" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";

-- ---------------------------------------------------------------------------
-- Storage RLS policies (storage.objects, bucket: poll-media)
-- ---------------------------------------------------------------------------

CREATE POLICY "Poll media is publicly readable"
ON storage.objects
FOR SELECT
USING (bucket_id = 'poll-media');

CREATE POLICY "Users can upload their own poll media"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'poll-media'
  AND (storage.foldername(name))[1] = (auth.uid())::text
);

CREATE POLICY "Users can update their own poll media"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'poll-media'
  AND (storage.foldername(name))[1] = (auth.uid())::text
)
WITH CHECK (
  bucket_id = 'poll-media'
  AND (storage.foldername(name))[1] = (auth.uid())::text
);

CREATE POLICY "Users can delete their own poll media"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'poll-media'
  AND (storage.foldername(name))[1] = (auth.uid())::text
);


CREATE OR REPLACE FUNCTION "public"."create_vote_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    poll_owner uuid;
    voter_name text;
    poll_question text;
begin
    select user_id, question into poll_owner, poll_question from polls where id = new.poll_id;
    if poll_owner is null or poll_owner = new.user_id then
        return new;
    end if;

    select coalesce(display_name, username) into voter_name from profiles where id = new.user_id;

    insert into notifications (user_id, type, title, message, related_poll_id, related_user_id)
    values (
        poll_owner,
        'vote',
        'New vote',
        coalesce(voter_name, 'Someone') || ' voted on "' || left(coalesce(poll_question, 'your poll'), 80) || '"',
        new.poll_id,
        new.user_id
    );

    return new;
end;
$$;


ALTER FUNCTION "public"."create_vote_notification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_like_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    poll_owner uuid;
    liker_name text;
    poll_question text;
begin
    select user_id, question into poll_owner, poll_question from polls where id = new.poll_id;
    if poll_owner is null or poll_owner = new.user_id then
        return new;
    end if;

    select coalesce(display_name, username) into liker_name from profiles where id = new.user_id;

    insert into notifications (user_id, type, title, message, related_poll_id, related_user_id)
    values (
        poll_owner,
        'like',
        'New like',
        coalesce(liker_name, 'Someone') || ' liked "' || left(coalesce(poll_question, 'your poll'), 80) || '"',
        new.poll_id,
        new.user_id
    );

    return new;
end;
$$;


ALTER FUNCTION "public"."create_like_notification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_comment_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    poll_owner uuid;
    commenter_name text;
    poll_question text;
begin
    if new.status <> 'active' then
        return new;
    end if;

    select user_id, question into poll_owner, poll_question from polls where id = new.poll_id;
    if poll_owner is null or poll_owner = new.user_id then
        return new;
    end if;

    select coalesce(display_name, username) into commenter_name from profiles where id = new.user_id;

    insert into notifications (user_id, type, title, message, related_poll_id, related_user_id)
    values (
        poll_owner,
        'comment',
        'New comment',
        coalesce(commenter_name, 'Someone') || ' commented on "' || left(coalesce(poll_question, 'your poll'), 80) || '"',
        new.poll_id,
        new.user_id
    );

    return new;
end;
$$;


ALTER FUNCTION "public"."create_comment_notification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_follow_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    follower_name text;
begin
    select coalesce(display_name, username) into follower_name from profiles where id = new.follower_id;

    insert into notifications (user_id, type, title, message, related_user_id)
    values (
        new.following_id,
        'follow',
        'New follower',
        coalesce(follower_name, 'Someone') || ' started following you',
        new.follower_id
    );

    return new;
end;
$$;


ALTER FUNCTION "public"."create_follow_notification"() OWNER TO "postgres";


CREATE OR REPLACE TRIGGER "trg_create_vote_notification" AFTER INSERT ON "public"."votes" FOR EACH ROW EXECUTE FUNCTION "public"."create_vote_notification"();



CREATE OR REPLACE TRIGGER "trg_create_like_notification" AFTER INSERT ON "public"."likes" FOR EACH ROW EXECUTE FUNCTION "public"."create_like_notification"();



CREATE OR REPLACE TRIGGER "trg_create_comment_notification" AFTER INSERT ON "public"."comments" FOR EACH ROW EXECUTE FUNCTION "public"."create_comment_notification"();



CREATE OR REPLACE TRIGGER "trg_create_follow_notification" AFTER INSERT ON "public"."follows" FOR EACH ROW EXECUTE FUNCTION "public"."create_follow_notification"();
