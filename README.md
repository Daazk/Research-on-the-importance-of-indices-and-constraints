# Звіт: вплив індексів на час виконання запитів


## Експеримент 1. Точковий пошук по Foreign Key

```sql
EXPLAIN ANALYZE SELECT * FROM rides WHERE client_id = 50000;
```

PostgreSQL не створює індекси для Foreign Key автоматично, тому без індексу база читає всю таблицю.

### До індексу

| Вузол плану | Execution Time |
|---|---|
| `Gather` - `Parallel Seq Scan on rides` | **103.068 ms** |

```
Gather                            - 2. збирає результати воркерів в один потік
  ->  Parallel Seq Scan on rides  - 1. кілька процесів читають усю таблицю і фільтрують client_id = 50000
```

### Створення індексу

```sql
CREATE INDEX idx_rides_client_id ON rides (client_id);
```

```
\d rides
Indexes:
    "rides_pkey" PRIMARY KEY, btree (id)
    "idx_rides_client_id" btree (client_id)
```

### Після індексу

| Вузол плану | Execution Time |
|---|---|
| `Bitmap Heap Scan` - `Bitmap Index Scan on idx_rides_client_id` | **0.335 ms** |

```
Bitmap Heap Scan on rides                      - 2. читає з таблиці лише знайдені сторінки
  ->  Bitmap Index Scan on idx_rides_client_id - 1. знаходить в індексі, на яких сторінках лежать рядки client_id = 50000
```

**Результат:** 103.068 / 0.335 ≈ у 307 разів швидше

---

## Експеримент 2. Фільтрація + сортування

```sql
EXPLAIN ANALYZE SELECT * FROM rides WHERE driver_id = 5000 ORDER BY ride_date DESC;
```

### До індексу

| Вузол плану | Execution Time |
|---|---|
| `Gather Merge` - `Sort` - `Parallel Seq Scan on rides` | **107.022 ms** |

```
Gather Merge                            - 3. збирає результати воркерів в один відсортований потік
  ->  Sort                              - 2. сортує за ride_date DESC
        ->  Parallel Seq Scan on rides  - 1. кілька процесів читають усю таблицю і фільтрують driver_id = 5000
```

### Створення індексу

```sql
CREATE INDEX idx_rides_driver_id ON rides (driver_id);
```

### Після індексу

| Вузол плану | Execution Time |
|---|---|
| `Sort` - `Bitmap Heap Scan` - `Bitmap Index Scan on idx_rides_driver_id` | **0.669 ms** |

```
Sort                                                 - 3. сортує за ride_date DESC
  ->  Bitmap Heap Scan on rides                      - 2. читає з таблиці лише знайдені сторінки
        ->  Bitmap Index Scan on idx_rides_driver_id - 1. знаходить в індексі, на яких сторінках лежать рядки driver_id = 5000
```

**Результат:** 107.022 / 0.669 ≈ у 159 разів швидше

---

## Експеримент 3. Композитний індекс

```sql
EXPLAIN ANALYZE SELECT COUNT(*) FROM rides
WHERE status = 'cancelled'
  AND ride_date >= '2026-07-01' AND ride_date < '2026-08-01';
```

### До індексу

| Вузол плану | Execution Time |
|---|---|
| `Parallel Seq Scan on rides` | **111.517 ms** |

```
Finalize Aggregate                            - 4. додає часткові результати і повертає підсумковий COUNT
  ->  Gather                                  - 3. збирає результати воркерів
        ->  Partial Aggregate                 - 2. кожен воркер рахує COUNT для своєї частини рядків
              ->  Parallel Seq Scan on rides  - 1. кілька процесів читають усю таблицю і фільтрують status та ride_date
```

### Варіант A: `(status, ride_date)`

```sql
CREATE INDEX idx_rides_status_date ON rides (status, ride_date);
```

| Вузол плану | Execution Time |
|---|---|
| `Index Only Scan using idx_rides_status_date` | **18.797 ms** |

```
Aggregate                                               - 2. рахує COUNT(*)
  ->  Index Only Scan using idx_rides_status_date       - 1. читає лише індекс, таблицю не відкриває: status і ride_date вже є в індексі
```

**Результат:** 111.517 / 18.797 ≈ у 5.9 раза швидше

### Варіант B: `(ride_date, status)`

```sql
DROP INDEX idx_rides_status_date;
CREATE INDEX idx_rides_date_status ON rides (ride_date, status);
```

| Вузол плану | Execution Time |
|---|---|
| `Index Only Scan using idx_rides_date_status` | **28.965 ms** |

```
Aggregate                                               - 2. рахує COUNT(*)
  ->  Index Only Scan using idx_rides_date_status       - 1. читає лише індекс, таблицю не відкриває: status і ride_date вже є в індексі
```

**Результат:** 111.517 / 28.965 ≈ у 3.8 раза швидше


### Чому `(status, ride_date)` швидший

B-tree індекс зберігає записи відсортованими **спочатку за першою колонкою, потім за другою** (як телефонний довідник: прізвище -> ім'я).

**Варіант A  `(status, ride_date)`:**


Усі записи з `status = 'cancelled'` лежать одним блоком, а всередині нього відсортовані за датою. PostgreSQL один раз спускається деревом одразу до точки `('cancelled', '2026-07-01')` і читає записи поспіль до `('cancelled', '2026-08-01')`. Кожен прочитаний запис відповідає умові, зайвих немає.

**Варіант B  `(ride_date, status)`:**


Перша колонка це діапазон, тому індекс може обмежити пошук лише за датою. Усередині діапазону записи відсортовані за часом, а не за статусом, і `cancelled` розкидані серед інших. База читає всі поїздки дати і для кожної перевіряє статус.

**Перевірка на цифрах (`EXPLAIN (ANALYZE, BUFFERS)`):**

| | Прочитано записів індексу | Прочитано сторінок |
|---|---|---|
| `(status, ride_date)` | 42 483 (лише потрібні) | 213 |
| `(ride_date, status)` | 169 830 (усі поїздки задоної дати) | 794 |

У другому варіанті читається приблизно в 4 рази більше даних, звідси й різниця в часі.


---

## Підсумкова таблиця

| # | Індекс | Тип сканування | Execution Time | Прискорення |
|---|---|---|---:|---:|
| 1 | - | Parallel Seq Scan | 103.068 ms | - |
| 1 | `(client_id)` | Bitmap Index Scan | 0.335 ms | **×307** |
| 2 | - | Parallel Seq Scan | 107.022 ms | - |
| 2 | `(driver_id)` | Bitmap Index Scan + Sort | 0.669 ms | **×159** |
| 3 | - | Parallel Seq Scan | 111.517 ms | - |
| 3 | `(status, ride_date)` | Index Only Scan | 18.797 ms | **×5.9** |
| 3 | `(ride_date, status)` | Index Only Scan | 28.965 ms | **×3.8** |
