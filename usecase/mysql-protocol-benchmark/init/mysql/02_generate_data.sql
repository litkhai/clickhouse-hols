-- MySQL 200만 유저 데이터 생성
-- 약 10-15분 소요

USE gamedb;

DELIMITER //

CREATE PROCEDURE generate_player_data(IN total_players INT, IN batch_size INT)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE batch_start INT DEFAULT 1;
    DECLARE batch_end INT;
    
    WHILE batch_start <= total_players DO
        SET batch_end = LEAST(batch_start + batch_size - 1, total_players);
        
        START TRANSACTION;
        
        SET i = batch_start;
        WHILE i <= batch_end DO
            INSERT INTO player_last_login (
                player_id, player_name, character_id, character_name,
                character_level, character_class, server_id, server_name,
                last_login_at, last_logout_at, last_ip, last_device_type,
                last_app_version, total_playtime_minutes, vip_level,
                guild_id, guild_name, last_map_id,
                last_position_x, last_position_y, last_position_z,
                currency_gold, currency_diamond, inventory_slots_used
            ) VALUES (
                i,
                CONCAT('Player_', i),
                i * 10 + FLOOR(RAND() * 5),
                CONCAT('Hero_', i, '_', FLOOR(RAND() * 100)),
                FLOOR(RAND() * 100) + 1,
                ELT(FLOOR(RAND() * 6) + 1, '전사','마법사','궁수','도적','성직자','소환사'),
                FLOOR(RAND() * 8) + 1,
                ELT(FLOOR(RAND() * 8) + 1, '아시아-1','아시아-2','유럽-1','유럽-2','북미-1','북미-2','남미-1','오세아니아-1'),
                DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 30) DAY),
                DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 30) DAY),
                CONCAT(FLOOR(RAND() * 256), '.', FLOOR(RAND() * 256), '.', FLOOR(RAND() * 256), '.', FLOOR(RAND() * 256)),
                ELT(FLOOR(RAND() * 4) + 1, 'iOS','Android','PC','Steam'),
                ELT(FLOOR(RAND() * 5) + 1, '1.0.0','1.0.1','1.1.0','1.2.0','1.2.1'),
                FLOOR(RAND() * 50000),
                FLOOR(RAND() * 11),
                IF(RAND() > 0.3, FLOOR(RAND() * 10000) + 1, NULL),
                IF(RAND() > 0.3, CONCAT('Guild_', FLOOR(RAND() * 1000)), NULL),
                FLOOR(RAND() * 200) + 1,
                RAND() * 1000,
                RAND() * 1000,
                RAND() * 100,
                FLOOR(RAND() * 100000000),
                FLOOR(RAND() * 10000),
                FLOOR(RAND() * 200)
            );
            SET i = i + 1;
        END WHILE;
        
        COMMIT;
        SELECT CONCAT('Inserted ', batch_end, ' / ', total_players) AS progress;
        SET batch_start = batch_end + 1;
    END WHILE;
END //

DELIMITER ;

-- 실행: 200만 rows 생성
CALL generate_player_data(2000000, 10000);

-- 검증
SELECT COUNT(*) AS total_players FROM player_last_login;
