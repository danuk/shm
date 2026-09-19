DELIMITER $$

DROP PROCEDURE IF EXISTS _convert_myisam_to_innodb$$

CREATE PROCEDURE _convert_myisam_to_innodb()
BEGIN
    DECLARE done  INT DEFAULT FALSE;
    DECLARE tbl   VARCHAR(255);
    DECLARE cur CURSOR FOR
        SELECT TABLE_NAME
        FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND ENGINE = 'MyISAM';
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO tbl;
        IF done THEN
            LEAVE read_loop;
        END IF;
        SET @_sql = CONCAT('ALTER TABLE `', tbl, '` ENGINE = InnoDB');
        PREPARE _stmt FROM @_sql;
        EXECUTE _stmt;
        DEALLOCATE PREPARE _stmt;
    END LOOP;
    CLOSE cur;
END$$

DELIMITER ;

CALL _convert_myisam_to_innodb();

DROP PROCEDURE IF EXISTS _convert_myisam_to_innodb;
