SET SERVEROUTPUT ON;

-- DROP OBJECTS

BEGIN EXECUTE IMMEDIATE 'DROP TABLE MAINTENANCE_LOG CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE ALERTS CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE HEALTH_STATUS CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE TELEMETRY_DATA CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE SATELLITE CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

BEGIN EXECUTE IMMEDIATE 'DROP SEQUENCE alert_seq'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP SEQUENCE telemetry_seq'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP VIEW SATELLITE_DASHBOARD'; EXCEPTION WHEN OTHERS THEN NULL; END;
/


-- TABLES
CREATE TABLE SATELLITE (
    Satellite_ID INT PRIMARY KEY,
    Name VARCHAR2(50) NOT NULL,
    Orbit_Type VARCHAR2(20),
    Status VARCHAR2(20) CHECK (Status IN ('Active','Inactive'))
);

CREATE TABLE TELEMETRY_DATA (
    Telemetry_ID INT PRIMARY KEY,
    Satellite_ID INT,
    Time_Stamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    Temperature NUMBER,
    Battery_Level NUMBER CHECK (Battery_Level BETWEEN 0 AND 100),
    Fuel_Level NUMBER CHECK (Fuel_Level BETWEEN 0 AND 100),
    Signal_Strength NUMBER,
    FOREIGN KEY (Satellite_ID) REFERENCES SATELLITE(Satellite_ID)
);

CREATE TABLE HEALTH_STATUS (
    Health_ID INT PRIMARY KEY,
    Satellite_ID INT,
    Overall_Status VARCHAR2(20) CHECK (Overall_Status IN ('Normal','Warning','Critical')),
    Last_Checked TIMESTAMP,
    FOREIGN KEY (Satellite_ID) REFERENCES SATELLITE(Satellite_ID)
);

CREATE TABLE ALERTS (
    Alert_ID INT PRIMARY KEY,
    Satellite_ID INT,
    Alert_Type VARCHAR2(50),
    Alert_Time TIMESTAMP,
    Severity VARCHAR2(20) CHECK (Severity IN ('Low','Medium','High','Critical')),
    FOREIGN KEY (Satellite_ID) REFERENCES SATELLITE(Satellite_ID)
);

CREATE TABLE MAINTENANCE_LOG (
    Log_ID INT PRIMARY KEY,
    Satellite_ID INT,
    Action_Taken VARCHAR2(100),
    Log_Date DATE,
    Result VARCHAR2(50),
    FOREIGN KEY (Satellite_ID) REFERENCES SATELLITE(Satellite_ID)
);

-- INDEX + SEQUENCES

CREATE INDEX idx_telemetry_sat ON TELEMETRY_DATA(Satellite_ID);

CREATE SEQUENCE alert_seq START WITH 1;
CREATE SEQUENCE telemetry_seq START WITH 100;

-- SAMPLE DATA

INSERT INTO SATELLITE VALUES (1,'INSAT','GEO','Active');
INSERT INTO SATELLITE VALUES (2,'GSAT','LEO','Active');
INSERT INTO SATELLITE VALUES (3,'CARTOSAT','MEO','Active');
INSERT INTO SATELLITE VALUES (4,'NAVIC','GEO','Active');
INSERT INTO SATELLITE VALUES (5,'RISAT','LEO','Inactive');

INSERT INTO HEALTH_STATUS VALUES (1,1,'Normal',CURRENT_TIMESTAMP);
INSERT INTO HEALTH_STATUS VALUES (2,2,'Normal',CURRENT_TIMESTAMP);
INSERT INTO HEALTH_STATUS VALUES (3,3,'Normal',CURRENT_TIMESTAMP);
INSERT INTO HEALTH_STATUS VALUES (4,4,'Normal',CURRENT_TIMESTAMP);
INSERT INTO HEALTH_STATUS VALUES (5,5,'Normal',CURRENT_TIMESTAMP);

COMMIT;

-- TRIGGER

CREATE OR REPLACE TRIGGER trg_auto_monitor
AFTER INSERT ON TELEMETRY_DATA
FOR EACH ROW
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '====================================');
    DBMS_OUTPUT.PUT_LINE('   TELEMETRY RECEIVED');
    DBMS_OUTPUT.PUT_LINE('   Satellite ID : ' || :NEW.Satellite_ID);
    DBMS_OUTPUT.PUT_LINE('------------------------------------');

    IF :NEW.Battery_Level < 20 THEN
        DBMS_OUTPUT.PUT_LINE('   [ALERT] Low Battery');
        INSERT INTO ALERTS
        SELECT alert_seq.NEXTVAL, :NEW.Satellite_ID, 'Low Battery', CURRENT_TIMESTAMP, 'Critical'
        FROM dual WHERE NOT EXISTS (
            SELECT 1 FROM ALERTS WHERE Satellite_ID=:NEW.Satellite_ID AND Alert_Type='Low Battery'
        );
    END IF;

    IF :NEW.Fuel_Level < 15 THEN
        DBMS_OUTPUT.PUT_LINE('   [ALERT] Low Fuel');
        INSERT INTO ALERTS
        SELECT alert_seq.NEXTVAL, :NEW.Satellite_ID, 'Low Fuel', CURRENT_TIMESTAMP, 'Critical'
        FROM dual WHERE NOT EXISTS (
            SELECT 1 FROM ALERTS WHERE Satellite_ID=:NEW.Satellite_ID AND Alert_Type='Low Fuel'
        );
    END IF;

    IF :NEW.Temperature > 65 THEN
        DBMS_OUTPUT.PUT_LINE('   [ALERT] High Temperature');
        INSERT INTO ALERTS
        SELECT alert_seq.NEXTVAL, :NEW.Satellite_ID, 'High Temperature', CURRENT_TIMESTAMP, 'High'
        FROM dual WHERE NOT EXISTS (
            SELECT 1 FROM ALERTS WHERE Satellite_ID=:NEW.Satellite_ID AND Alert_Type='High Temperature'
        );
    END IF;

    IF :NEW.Signal_Strength < 30 THEN
        DBMS_OUTPUT.PUT_LINE('   [ALERT] Weak Signal');
        INSERT INTO ALERTS
        SELECT alert_seq.NEXTVAL, :NEW.Satellite_ID, 'Weak Signal', CURRENT_TIMESTAMP, 'Medium'
        FROM dual WHERE NOT EXISTS (
            SELECT 1 FROM ALERTS WHERE Satellite_ID=:NEW.Satellite_ID AND Alert_Type='Weak Signal'
        );
    END IF;

    UPDATE HEALTH_STATUS
    SET Overall_Status =
        CASE
            WHEN :NEW.Battery_Level < 20 OR :NEW.Fuel_Level < 15 THEN 'Critical'
            WHEN :NEW.Temperature > 65 OR :NEW.Signal_Strength < 30 THEN 'Warning'
            ELSE 'Normal'
        END,
        Last_Checked = CURRENT_TIMESTAMP
    WHERE Satellite_ID = :NEW.Satellite_ID;

    DBMS_OUTPUT.PUT_LINE('------------------------------------');
    DBMS_OUTPUT.PUT_LINE('   → Health Status Updated');
    DBMS_OUTPUT.PUT_LINE('====================================' || CHR(10));
END;
/


CREATE OR REPLACE TRIGGER trg_maintenance_log
AFTER INSERT ON ALERTS
FOR EACH ROW
BEGIN
    IF :NEW.Severity = 'Critical' THEN
        INSERT INTO MAINTENANCE_LOG
        VALUES (
            (SELECT NVL(MAX(Log_ID),0)+1 FROM MAINTENANCE_LOG),
            :NEW.Satellite_ID,
            'Auto Maintenance Required: ' || :NEW.Alert_Type,
            SYSDATE,
            'Pending'
        );

        DBMS_OUTPUT.PUT_LINE('   [MAINTENANCE] Logged for Satellite ' || :NEW.Satellite_ID);
    END IF;
END;
/

-- PROCEDURE

CREATE OR REPLACE PROCEDURE insert_telemetry(
    p_sid INT, p_temp NUMBER, p_bat NUMBER, p_fuel NUMBER, p_sig NUMBER)
AS
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '>>> INSERTING TELEMETRY');
    DBMS_OUTPUT.PUT_LINE('    Satellite ID : ' || p_sid);
    DBMS_OUTPUT.PUT_LINE('------------------------------------');

    INSERT INTO TELEMETRY_DATA VALUES (
        telemetry_seq.NEXTVAL, p_sid, CURRENT_TIMESTAMP,
        p_temp, p_bat, p_fuel, p_sig
    );
END;
/

-- RANDOM GENERATOR

CREATE OR REPLACE PROCEDURE generate_random_telemetry(p_count INT DEFAULT 5)
AS
    v_total INT := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '====================================');
    DBMS_OUTPUT.PUT_LINE('   RANDOM TELEMETRY GENERATION START');
    DBMS_OUTPUT.PUT_LINE('====================================');

    FOR sat IN (SELECT Satellite_ID FROM SATELLITE WHERE Status='Active') LOOP
        FOR i IN 1..p_count LOOP
            insert_telemetry(
                sat.Satellite_ID,
                ROUND(DBMS_RANDOM.VALUE(-10,80),2),
                ROUND(DBMS_RANDOM.VALUE(5,100),2),
                ROUND(DBMS_RANDOM.VALUE(5,100),2),
                ROUND(DBMS_RANDOM.VALUE(10,100),2)
            );
            v_total := v_total + 1;
        END LOOP;
    END LOOP;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('------------------------------------');
    DBMS_OUTPUT.PUT_LINE('   Total Records Inserted : ' || v_total);
    DBMS_OUTPUT.PUT_LINE('====================================' || CHR(10));
END;
/


-- FUNCTION

CREATE OR REPLACE FUNCTION get_health_score(p_sid INT)
RETURN NUMBER
AS
    v_bat NUMBER;
    v_fuel NUMBER;
    v_temp NUMBER;
BEGIN
    SELECT Battery_Level, Fuel_Level, Temperature
    INTO v_bat, v_fuel, v_temp
    FROM TELEMETRY_DATA
    WHERE Satellite_ID = p_sid
    ORDER BY Time_Stamp DESC
    FETCH FIRST 1 ROW ONLY;

    RETURN ROUND(v_bat*0.4 + v_fuel*0.4 - CASE WHEN v_temp>65 THEN 10 ELSE 0 END,2);

EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN 0;
END;
/


-- VIEW

CREATE OR REPLACE VIEW SATELLITE_DASHBOARD AS
SELECT S.Name, H.Overall_Status, T.Temperature, T.Battery_Level,
       T.Fuel_Level, T.Signal_Strength, T.Time_Stamp
FROM SATELLITE S
JOIN HEALTH_STATUS H ON S.Satellite_ID = H.Satellite_ID
JOIN (
    SELECT t.*
    FROM TELEMETRY_DATA t
    JOIN (
        SELECT Satellite_ID, MAX(Time_Stamp) AS max_ts
        FROM TELEMETRY_DATA GROUP BY Satellite_ID
    ) latest
    ON t.Satellite_ID = latest.Satellite_ID
    AND t.Time_Stamp = latest.max_ts
) T ON S.Satellite_ID = T.Satellite_ID;

-- MAIN EXECUTION

BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '====================================');
    DBMS_OUTPUT.PUT_LINE('           SYSTEM START');
    DBMS_OUTPUT.PUT_LINE('====================================');

    insert_telemetry(1,70,15,50,80);
    insert_telemetry(2,80,60,10,70);

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- Manual Insert Completed ---');

    generate_random_telemetry(3);

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '====================================');
    DBMS_OUTPUT.PUT_LINE('           SYSTEM END');
    DBMS_OUTPUT.PUT_LINE('====================================' || CHR(10));
END;
/



-- DATA RETRIEVAL (FINAL OUTPUT)


-- All alerts generated
SELECT * FROM ALERTS;

-- Dashboard view (latest telemetry + health)
SELECT Name, Overall_Status, Temperature, Battery_Level
FROM SATELLITE_DASHBOARD;

-- Count of alerts per satellite
SELECT Satellite_ID, COUNT(*) AS Total_Alerts
FROM ALERTS
GROUP BY Satellite_ID;

-- Satellites with critical alerts
SELECT Name 
FROM SATELLITE 
WHERE Satellite_ID IN (
    SELECT Satellite_ID 
    FROM ALERTS 
    WHERE Severity = 'Critical'
);

-- Health score using function
SELECT Name, get_health_score(Satellite_ID) AS Health_Score
FROM SATELLITE;

-- Maintenance history of satellites
SELECT * FROM MAINTENANCE_LOG;


SELECT * FROM health_status;
