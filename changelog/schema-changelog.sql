--liquibase formatted sql

--changeset repro-author:1
CREATE TABLE testschema.event_data
(
    eventId   INTEGER,
    eventName VARCHAR(128),
    createdAt TIMESTAMP DEFAULT NOW()
);

--changeset repro-author:2
INSERT INTO testschema.event_data(eventId, eventName) VALUES (1, 'bootstrap-event');
