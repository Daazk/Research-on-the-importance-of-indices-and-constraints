CREATE TABLE clients (
    id SERIAL PRIMARY KEY,
    phone VARCHAR(20) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    rating NUMERIC DEFAULT 5.0
        CHECK(rating >= 1 AND rating <= 5)
);

CREATE TABLE drivers (
    id SERIAL PRIMARY KEY,
    license_number VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    status VARCHAR(20)
        CHECK(status IN ('active', 'blocked', 'on_vacation'))
);

CREATE TABLE rides (
    id SERIAL PRIMARY KEY,
    client_id INTEGER NOT NULL,
    driver_id INTEGER NOT NULL,
    ride_date TIMESTAMP NOT NULL,
    status VARCHAR(20)
        CHECK(status IN ('requested', 'ongoing', 'completed', 'cancelled')),
    price NUMERIC
        CHECK(price > 0),

    FOREIGN KEY (client_id)
        REFERENCES clients(id)
        ON DELETE CASCADE,

    FOREIGN KEY (driver_id)
        REFERENCES drivers(id)
        ON DELETE RESTRICT
);
