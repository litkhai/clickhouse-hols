-- MySQL 스키마: 플레이어 마지막 접속 정보 테이블
USE gamedb;

CREATE TABLE player_last_login (
    player_id BIGINT PRIMARY KEY,
    player_name VARCHAR(64) NOT NULL,
    character_id BIGINT NOT NULL,
    character_name VARCHAR(64) NOT NULL,
    character_level INT NOT NULL,
    character_class VARCHAR(32) NOT NULL,
    server_id INT NOT NULL,
    server_name VARCHAR(32) NOT NULL,
    last_login_at DATETIME(3) NOT NULL,
    last_logout_at DATETIME(3),
    last_ip VARCHAR(45),
    last_device_type VARCHAR(32),
    last_app_version VARCHAR(16),
    total_playtime_minutes INT DEFAULT 0,
    vip_level TINYINT DEFAULT 0,
    guild_id BIGINT,
    guild_name VARCHAR(64),
    last_map_id INT,
    last_position_x FLOAT,
    last_position_y FLOAT,
    last_position_z FLOAT,
    currency_gold BIGINT DEFAULT 0,
    currency_diamond INT DEFAULT 0,
    inventory_slots_used INT DEFAULT 0,
    created_at DATETIME(3) DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
