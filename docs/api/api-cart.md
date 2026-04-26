# Cart API Documentation

## Описание
Серверная корзина с привязкой к пользователю. Данные хранятся в БД, синхронизируются между устройствами.

## База данных

### Таблица `cart_items`
- `id` - PRIMARY KEY
- `user_id` - FOREIGN KEY (users.id) CASCADE DELETE
- `product_id` - FOREIGN KEY (products.id) CASCADE DELETE
- `quantity` - INTEGER DEFAULT 1
- `created_at`, `updated_at` - TIMESTAMPS
- **UNIQUE CONSTRAINT** (user_id, product_id) - предотвращает дублирование
- **INDEX** (user_id, created_at) - для оптимизации запросов

## API Endpoints

Все endpoints требуют аутентификации через middleware `auth:web`.

### 1. GET /api/cart
**Описание:** Получить корзину текущего пользователя

**Response:**
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": 1,
        "product_id": 5,
        "name": "Product name",
        "price": 800,
        "price_formatted": "800 ₽",
        "quantity": 2,
        "total_price": 1600,
        "total_price_formatted": "1 600 ₽",
        "image": "http://example.com/image.jpg",
        "seller_id": 7,
        "seller_name": "Seller Name",
        "seller": {
          "id": 7,
          "name": "Seller Name",
          "username": "seller123",
          "is_store": true
        },
        "is_available": true,
        "stock_quantity": 10,
        "status": "active",
        "product": {
          "id": 5,
          "title": "Product name",
          "slug": "product-name",
          "condition": "used",
          "location": "Moscow",
          "shipping_cost": "250.00",
          "can_trade": false,
          "url": "http://example.com/products/5"
        },
        "created_at": "2025-10-02T20:00:00.000000Z",
        "updated_at": "2025-10-02T20:00:00.000000Z",
        "added_at": "02.10.2025 20:00"
      }
    ],
    "summary": {
      "total_price": 1600,
      "total_price_formatted": "1 600 ₽",
      "total_items": 1,
      "total_quantity": 2
    }
  }
}
```

### 2. POST /api/cart
**Описание:** Добавить товар в корзину

**Request Body:**
```json
{
  "product_id": 5,
  "quantity": 2  // optional, default: 1
}
```

**Валидация:**
- `product_id`: required, integer, exists:products, active status, не удален
- `quantity`: optional, integer, min:1, max:100
- Проверка: пользователь не может добавить свой товар
- Проверка: товар должен быть в наличии (stock_quantity >= quantity)

**Response (201 Created):**
```json
{
  "success": true,
  "message": "Товар добавлен в корзину",
  "data": { /* CartResource */ }
}
```

**Response (200 OK) - если товар уже в корзине:**
```json
{
  "success": true,
  "message": "Количество товара в корзине обновлено",
  "data": { /* CartResource */ }
}
```

**Поведение:** Если товар уже в корзине, увеличивается quantity

### 3. PATCH /api/cart/{cartItem}
**Описание:** Обновить количество товара в корзине

**Request Body:**
```json
{
  "quantity": 5
}
```

**Валидация:**
- `quantity`: required, integer, min:1, max:100
- Проверка: товар доступен (status = active)
- Проверка: достаточно на складе (stock_quantity >= quantity)

**Authorization:** Пользователь может изменять только свою корзину

**Response (200 OK):**
```json
{
  "success": true,
  "message": "Количество товара обновлено",
  "data": { /* CartResource */ }
}
```

### 4. DELETE /api/cart/{cartItem}
**Описание:** Удалить товар из корзины

**Authorization:** Пользователь может удалять только из своей корзины

**Response (200 OK):**
```json
{
  "success": true,
  "message": "Товар удален из корзины"
}
```

### 5. DELETE /api/cart
**Описание:** Очистить всю корзину

**Response (200 OK):**
```json
{
  "success": true,
  "message": "Корзина очищена. Удалено товаров: 3",
  "deleted_count": 3
}
```

## Модели

### CartItem Model
**Файл:** `/app/Models/CartItem.php`

**Relationships:**
- `user()` - belongsTo User
- `product()` - belongsTo Product (with eager loading of user)

**Accessors:**
- `image` - URL первого изображения товара
- `seller_name` - имя продавца
- `seller_id` - ID продавца
- `total_price` - общая стоимость позиции (price * quantity)

**Methods:**
- `isAvailable()` - проверка доступности товара
- `scopeForUser($userId)` - scope для фильтрации по пользователю
- `scopeWithRelations()` - scope с eager loading связей

### User Model (дополнения)
**Файл:** `/app/Models/User.php`

**Relationships:**
- `cartItems()` - hasMany CartItem
- `cartProducts()` - belongsToMany Product через cart_items

### Product Model (дополнения)
**Файл:** `/app/Models/Product.php`

**Relationships:**
- `cartItems()` - hasMany CartItem
- `inCartByUsers()` - belongsToMany User через cart_items

## Policy

### CartItemPolicy
**Файл:** `/app/Policies/CartItemPolicy.php`

**Правила:**
- `viewAny()` - любой авторизованный пользователь может просматривать свою корзину
- `view()` - только свою корзину
- `create()` - проверки:
  - Пользователь активен
  - Телефон подтвержден
  - Товар активен и не удален
  - Нельзя добавлять собственные товары
  - Товар в наличии (stock_quantity >= 1)
- `update()` - только свою корзину, товар должен быть доступен
- `delete()` - только из своей корзины
- `clearAll()` - пользователь должен быть активен

## Form Requests

### AddToCartRequest
**Файл:** `/app/Http/Requests/Cart/AddToCartRequest.php`

**Валидация:**
- product_id: required, integer, exists, active, не удален
- quantity: optional, integer, min:1, max:100

**Дополнительные проверки:**
- Товар не принадлежит пользователю
- Достаточно товара на складе

### UpdateCartItemRequest
**Файл:** `/app/Http/Requests/Cart/UpdateCartItemRequest.php`

**Валидация:**
- quantity: required, integer, min:1, max:100

**Authorization:** Корзина принадлежит пользователю

**Дополнительные проверки:**
- Товар активен
- Достаточно на складе

## Resources

### CartResource
**Файл:** `/app/Http/Resources/CartResource.php`

**Возвращаемые поля:**
- Базовая информация: id, product_id, name, price, quantity
- Расчеты: total_price, price_formatted, total_price_formatted
- Медиа: image
- Продавец: seller_id, seller_name, seller (объект)
- Доступность: is_available, stock_quantity, status
- Товар: product (полная информация)
- Временные метки: created_at, updated_at, added_at

## Примеры использования

### JavaScript (Fetch API)
```javascript
// Получить корзину
const response = await fetch('/api/cart', {
  credentials: 'include'
});
const data = await response.json();

// Добавить товар
await fetch('/api/cart', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-CSRF-TOKEN': document.querySelector('meta[name="csrf-token"]').content
  },
  credentials: 'include',
  body: JSON.stringify({
    product_id: 5,
    quantity: 2
  })
});

// Обновить количество
await fetch(`/api/cart/${cartItemId}`, {
  method: 'PATCH',
  headers: {
    'Content-Type': 'application/json',
    'X-CSRF-TOKEN': document.querySelector('meta[name="csrf-token"]').content
  },
  credentials: 'include',
  body: JSON.stringify({
    quantity: 5
  })
});

// Удалить товар
await fetch(`/api/cart/${cartItemId}`, {
  method: 'DELETE',
  headers: {
    'X-CSRF-TOKEN': document.querySelector('meta[name="csrf-token"]').content
  },
  credentials: 'include'
});

// Очистить корзину
await fetch('/api/cart', {
  method: 'DELETE',
  headers: {
    'X-CSRF-TOKEN': document.querySelector('meta[name="csrf-token"]').content
  },
  credentials: 'include'
});
```

## Логирование

Все операции с корзиной логируются:
- Добавление товара
- Обновление количества
- Удаление товара
- Очистка корзины

Логи содержат: user_id, product_id, cart_item_id, old/new quantity

## Транзакции

Операции добавления и обновления используют DB транзакции для обеспечения консистентности данных.

## Особенности реализации

1. **Unique Constraint:** Предотвращает дублирование товаров в корзине одного пользователя
2. **Cascade Delete:** При удалении пользователя или товара автоматически удаляются записи корзины
3. **Eager Loading:** Автоматическая загрузка связанных данных (product.user) для оптимизации запросов
4. **Проверка доступности:** Перед добавлением/обновлением проверяется stock_quantity
5. **Auto-increment:** При добавлении существующего товара увеличивается quantity вместо создания дубликата
