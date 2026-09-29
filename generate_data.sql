INSERT INTO clients (phone, email, rating)
SELECT
    '+38000' || LPAD(i::text, 7, '0'),
    'client' || i || '@test.com',
    (random() * 4 + 1)::numeric(2,1)
FROM generate_series(1, 100000) s(i);

INSERT INTO drivers (license_number, name, status)
SELECT
    'LIC' || LPAD(i::text, 7, '0'),
    'Driver ' || i,
    (ARRAY['active', 'blocked', 'on_vacation'])[floor(random() * 3 + 1)]
FROM generate_series(1, 10000) s(i);

INSERT INTO rides (client_id, driver_id, ride_date, status, price)
SELECT
    (random() * 99999 + 1)::int,
    (random() * 9999 + 1)::int,
    NOW() - (random() * 365 || ' days')::interval,
    (ARRAY['requested', 'ongoing', 'completed', 'cancelled'])[floor(random() * 4 + 1)],
    (random() * 500 + 50)::numeric(10,2)
FROM generate_series(1, 2000000) s(i);
