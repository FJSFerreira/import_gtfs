-- GTFS Schedule schema for PostgreSQL.
-- IDs intentionally use TEXT: GTFS IDs are identifiers, not necessarily numbers.
-- GTFS service times remain TEXT because valid values can exceed 24:00:00.
-- Date fields use DATE; PostgreSQL accepts GTFS YYYYMMDD date input.
-- =========================================================
-- CORE GTFS TABLES
-- =========================================================

CREATE TABLE {schema}.agency (
    agency_id TEXT PRIMARY KEY,
    agency_name TEXT NOT NULL,
    agency_url TEXT NOT NULL,
    agency_timezone TEXT NOT NULL,
    agency_lang TEXT,
    agency_phone TEXT,
    agency_fare_url TEXT,
    agency_email TEXT
);

CREATE TABLE {schema}.stops (
    stop_id TEXT PRIMARY KEY,
    stop_code TEXT,
    stop_name TEXT,
    tts_stop_name TEXT,
    stop_desc TEXT,
    stop_lat DOUBLE PRECISION,
    stop_lon DOUBLE PRECISION,
    zone_id TEXT,
    stop_url TEXT,
    location_type SMALLINT,
    parent_station TEXT,
    stop_timezone TEXT,
    wheelchair_boarding SMALLINT,
    level_id TEXT,
    platform_code TEXT,
    vehicle_type INTEGER
);

CREATE TABLE {schema}.routes (
    route_id TEXT PRIMARY KEY,
    agency_id TEXT,
    route_short_name TEXT,
    route_long_name TEXT,
    route_desc TEXT,
    route_type INTEGER,
    route_url TEXT,
    route_color TEXT,
    route_text_color TEXT,
    route_sort_order INTEGER,
    continuous_pickup SMALLINT,
    continuous_drop_off SMALLINT,
    network_id TEXT,
    as_route TEXT
);

CREATE TABLE {schema}.calendar (
    service_id TEXT PRIMARY KEY,
    monday SMALLINT NOT NULL,
    tuesday SMALLINT NOT NULL,
    wednesday SMALLINT NOT NULL,
    thursday SMALLINT NOT NULL,
    friday SMALLINT NOT NULL,
    saturday SMALLINT NOT NULL,
    sunday SMALLINT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL
);

CREATE TABLE {schema}.calendar_dates (
    service_id TEXT NOT NULL,
    date DATE NOT NULL,
    exception_type SMALLINT NOT NULL,
    PRIMARY KEY (service_id, date)
);

CREATE TABLE {schema}.shapes (
    shape_id TEXT NOT NULL,
    shape_pt_lat DOUBLE PRECISION NOT NULL,
    shape_pt_lon DOUBLE PRECISION NOT NULL,
    shape_pt_sequence INTEGER NOT NULL,
    shape_dist_traveled DOUBLE PRECISION,
    PRIMARY KEY (shape_id, shape_pt_sequence)
);

CREATE TABLE {schema}.trips (
    route_id TEXT NOT NULL,
    service_id TEXT NOT NULL,
    trip_id TEXT PRIMARY KEY,
    trip_headsign TEXT,
    trip_short_name TEXT,
    direction_id SMALLINT,
    block_id TEXT,
    shape_id TEXT,
    wheelchair_accessible SMALLINT,
    bikes_allowed SMALLINT,
    cars_allowed SMALLINT
);

CREATE TABLE {schema}.stop_times (
    trip_id TEXT NOT NULL,
    arrival_time TEXT,
    departure_time TEXT,
    stop_id TEXT NOT NULL,
    location_group_id TEXT,
    location_id TEXT,
    stop_sequence INTEGER NOT NULL,
    stop_headsign TEXT,
    start_pickup_drop_off_window TEXT,
    end_pickup_drop_off_window TEXT,
    pickup_type SMALLINT,
    drop_off_type SMALLINT,
    continuous_pickup SMALLINT,
    continuous_drop_off SMALLINT,
    shape_dist_traveled DOUBLE PRECISION,
    timepoint SMALLINT,
    pickup_booking_rule_id TEXT,
    drop_off_booking_rule_id TEXT,
    PRIMARY KEY (trip_id, stop_sequence)
);

CREATE TABLE {schema}.frequencies (
    trip_id TEXT NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    headway_secs INTEGER NOT NULL,
    exact_times SMALLINT,
    PRIMARY KEY (trip_id, start_time)
);

CREATE TABLE {schema}.transfers (
    from_stop_id TEXT,
    to_stop_id TEXT,
    from_route_id TEXT,
    to_route_id TEXT,
    from_trip_id TEXT,
    to_trip_id TEXT,
    transfer_type SMALLINT NOT NULL,
    min_transfer_time INTEGER
);

-- =========================================================
-- PLANS
-- =========================================================

CREATE TABLE {schema}.plans (
    agency_id TEXT NOT NULL,
    plan_end_date DATE NOT NULL,
    plan_id TEXT PRIMARY KEY,
    plan_start_date DATE NOT NULL
);

-- =========================================================
-- GTFS PATHWAYS
-- =========================================================

CREATE TABLE {schema}.levels (
    level_id TEXT PRIMARY KEY,
    level_index DOUBLE PRECISION NOT NULL,
    level_name TEXT
);

CREATE TABLE {schema}.pathways (
    pathway_id TEXT PRIMARY KEY,
    from_stop_id TEXT NOT NULL,
    to_stop_id TEXT NOT NULL,
    pathway_mode SMALLINT NOT NULL,
    is_bidirectional SMALLINT NOT NULL,
    length DOUBLE PRECISION,
    traversal_time INTEGER,
    stair_count INTEGER,
    max_slope DOUBLE PRECISION,
    min_width DOUBLE PRECISION,
    signposted_as TEXT,
    reversed_signposted_as TEXT
);

-- =========================================================
-- GTFS FARES V1
-- =========================================================

CREATE TABLE {schema}.fare_attributes (
    fare_id TEXT PRIMARY KEY,
    price NUMERIC(12, 4) NOT NULL,
    currency_type TEXT NOT NULL,
    payment_method SMALLINT NOT NULL,
    transfers SMALLINT,
    agency_id TEXT,
    transfer_duration INTEGER
);

CREATE TABLE {schema}.fare_rules (
    fare_id TEXT NOT NULL,
    route_id TEXT,
    origin_id TEXT,
    destination_id TEXT,
    contains_id TEXT
);

-- =========================================================
-- GTFS FARES V2
-- =========================================================

CREATE TABLE {schema}.rider_categories (
    rider_category_id TEXT PRIMARY KEY,
    rider_category_name TEXT,
    is_default_fare_category SMALLINT,
    eligibility_url TEXT,
    eligibility_url_text TEXT
);

CREATE TABLE {schema}.fare_media (
    fare_media_id TEXT PRIMARY KEY,
    fare_media_name TEXT,
    fare_media_type SMALLINT NOT NULL
);

CREATE TABLE {schema}.fare_products (
    fare_product_id TEXT NOT NULL,
    fare_product_name TEXT,
    rider_category_id TEXT NOT NULL,
    fare_media_id TEXT NOT NULL,
    amount NUMERIC(12, 4) NOT NULL,
    currency TEXT NOT NULL,
    PRIMARY KEY (fare_product_id, rider_category_id, fare_media_id)
);

CREATE TABLE {schema}.fare_leg_rules (
    leg_group_id TEXT,
    network_id TEXT,
    from_area_id TEXT,
    to_area_id TEXT,
    fare_product_id TEXT NOT NULL,
    rider_category_id TEXT,
    fare_media_id TEXT,
    timeframe_group_id TEXT
);

CREATE TABLE {schema}.fare_leg_join_rules (
    from_network_id TEXT,
    to_network_id TEXT,
    from_stop_id TEXT,
    to_stop_id TEXT,
    from_fare_product_id TEXT,
    to_fare_product_id TEXT,
    fare_product_id TEXT NOT NULL
);

CREATE TABLE {schema}.fare_transfer_rules (
    from_leg_group_id TEXT,
    to_leg_group_id TEXT,
    transfer_count SMALLINT,
    duration_limit INTEGER,
    duration_limit_type SMALLINT,
    fare_transfer_type SMALLINT NOT NULL,
    fare_product_id TEXT,
    from_network_id TEXT,
    to_network_id TEXT,
    from_area_id TEXT,
    to_area_id TEXT,
    fare_media_id TEXT
);

CREATE TABLE {schema}.timeframes (
    timeframe_group_id TEXT NOT NULL,
    start_time TIME,
    end_time TIME,
    service_id TEXT NOT NULL,
    PRIMARY KEY (timeframe_group_id, service_id)
);

CREATE TABLE {schema}.networks (
    network_id TEXT PRIMARY KEY,
    network_name TEXT
);

CREATE TABLE {schema}.route_networks (
    network_id TEXT NOT NULL,
    route_id TEXT NOT NULL,
    PRIMARY KEY (network_id, route_id)
);

CREATE TABLE {schema}.areas (
    area_id TEXT PRIMARY KEY,
    area_name TEXT
);

CREATE TABLE {schema}.stop_areas (
    area_id TEXT NOT NULL,
    stop_id TEXT NOT NULL,
    PRIMARY KEY (area_id, stop_id)
);

-- =========================================================
-- GTFS FLEX / ON-DEMAND SERVICES
-- =========================================================

CREATE TABLE {schema}.location_groups (
    location_group_id TEXT PRIMARY KEY,
    location_group_name TEXT
);

CREATE TABLE {schema}.location_group_stops (
    location_group_id TEXT NOT NULL,
    stop_id TEXT NOT NULL,
    PRIMARY KEY (location_group_id, stop_id)
);

CREATE TABLE {schema}.locations_geojson (
    feature_id TEXT PRIMARY KEY,
    feature JSONB NOT NULL
);

CREATE TABLE {schema}.booking_rules (
    booking_rule_id TEXT PRIMARY KEY,
    booking_type SMALLINT NOT NULL,
    prior_notice_duration_min INTEGER,
    prior_notice_duration_max INTEGER,
    prior_notice_last_day INTEGER,
    prior_notice_last_time TIME,
    prior_notice_start_day INTEGER,
    prior_notice_start_time TIME,
    prior_notice_service_id TEXT,
    message TEXT,
    pickup_message TEXT,
    drop_off_message TEXT,
    phone_number TEXT,
    info_url TEXT,
    booking_url TEXT
);

-- =========================================================
-- TRANSLATIONS / FEED METADATA
-- =========================================================

CREATE TABLE {schema}.translations (
    table_name TEXT NOT NULL,
    field_name TEXT NOT NULL,
    language TEXT NOT NULL,
    translation TEXT NOT NULL,
    record_id TEXT,
    record_sub_id TEXT,
    field_value TEXT
);

CREATE TABLE {schema}.feed_info (
    feed_publisher_name TEXT NOT NULL,
    feed_publisher_url TEXT NOT NULL,
    feed_lang TEXT NOT NULL,
    default_lang TEXT,
    feed_start_date TEXT,
    feed_end_date TEXT,
    feed_version TEXT,
    feed_contact_email TEXT,
    feed_contact_url TEXT
);

CREATE TABLE {schema}.attributions (
    attribution_id TEXT PRIMARY KEY,
    agency_id TEXT,
    route_id TEXT,
    trip_id TEXT,
    organization_name TEXT NOT NULL,
    is_producer SMALLINT,
    is_operator SMALLINT,
    is_authority SMALLINT,
    attribution_url TEXT,
    attribution_email TEXT,
    attribution_phone TEXT
);
