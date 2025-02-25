import asyncio
import logging
import aiosqlite
import datetime
from aiogram import Bot, Dispatcher, types, F
from aiogram.types import InlineKeyboardMarkup, InlineKeyboardButton
from aiogram.enums import ParseMode
from aiogram.filters import CommandStart
from aiogram.client.default import DefaultBotProperties

# Настройки бота
TOKEN = "7967860347:AAHUs2UBmU-NIqSm3l5vK6_jRl-bW8dL-co"  # Замените на действительный токен
BOT_USERNAME = "PajohnKeyBot"
CHANNELS = [
    {"id": "@Gamesgaben", "link": "https://t.me/Gamesgaben"},
    {"id": "@PaJohn66", "link": "https://t.me/PaJohn66"},
]

bot = Bot(token=TOKEN, default=DefaultBotProperties(parse_mode=ParseMode.HTML))
dp = Dispatcher()
logging.basicConfig(level=logging.INFO)

# Инициализация базы данных: таблица пользователей и рефералов
async def init_db():
    async with aiosqlite.connect("database.db") as db:
        await db.execute("""
            CREATE TABLE IF NOT EXISTS users (
                user_id INTEGER PRIMARY KEY,
                referrals INTEGER DEFAULT 0,
                last_key_date TEXT DEFAULT ''
            )
        """)
        await db.execute("""
            CREATE TABLE IF NOT EXISTS referrals (
                user_id INTEGER PRIMARY KEY,
                referrer_id INTEGER
            )
        """)
        await db.commit()

# Функция для получения ключа из файла key.txt (один на строку)
async def get_key_from_file():
    try:
        with open("key.txt", "r") as file:
            keys = file.readlines()
        if keys:
            key = keys[0].strip()
            with open("key.txt", "w") as file:
                file.writelines(keys[1:])
            return key
    except FileNotFoundError:
        return None
    return None

# Регистрация пользователя и обработка рефералов
async def register_user(user_id: int, referrer_id: int = None):
    async with aiosqlite.connect("database.db") as db:
        # Вставляем пользователя, если его ещё нет
        await db.execute("INSERT OR IGNORE INTO users (user_id) VALUES (?)", (user_id,))
        # Если передан реферальный id и пользователь не равен рефереру
        if referrer_id and user_id != referrer_id:
            async with db.execute("SELECT referrer_id FROM referrals WHERE user_id = ?", (user_id,)) as cursor:
                exists = await cursor.fetchone()
            if not exists:
                # Регистрируем реферала
                await db.execute("INSERT INTO referrals (user_id, referrer_id) VALUES (?, ?)", (user_id, referrer_id))
                # Увеличиваем счетчик приглашённых у реферера
                await db.execute("UPDATE users SET referrals = referrals + 1 WHERE user_id = ?", (referrer_id,))
                async with db.execute("SELECT referrals FROM users WHERE user_id = ?", (referrer_id,)) as cursor:
                    row = await cursor.fetchone()
                    count = row[0] if row else 0
                # Если достигнуто кратное 5 приглашений – высылаем бонусный ключ рефереру
                if count % 5 == 0:
                    key = await get_key_from_file()
                    if key:
                        await bot.send_message(referrer_id, f"\U0001F389 Поздравляем! За приглашение 5 друзей твой бонусный ключ: {key}")
        await db.commit()

# Проверка подписки пользователя на все каналы
async def check_subscription(user_id: int) -> bool:
    for channel in CHANNELS:
        chat_member = await bot.get_chat_member(channel["id"], user_id)
        if chat_member.status not in ("member", "administrator", "creator"):
            return False
    return True

# Обработчик команды /start: регистрирует пользователя и выводит клавиатуру с обновленным текстом
@dp.message(CommandStart())
async def start(message: types.Message):
    user_id = message.from_user.id
    args = message.text.split()
    referrer_id = int(args[1]) if len(args) > 1 and args[1].isdigit() else None
    await register_user(user_id, referrer_id)
    
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="✅ Проверить подписку", callback_data="check_sub")],
        [InlineKeyboardButton(text="📩 Пригласить друзей", callback_data="invite_friends")],
        [InlineKeyboardButton(text="🎮 Получить ключ", callback_data="get_key")],
        [InlineKeyboardButton(text="📊 Мои рефералы", callback_data="my_referrals")],
        [InlineKeyboardButton(text="⏱ Таймер", callback_data="timer")]
    ])
    
    # Новый текст приветствия
    text = (
        "\U0001F44B Привет, друг! Я щедрый бот, который раздает ключи от игр Steam \U0001F3AE\n\n"
        "✅ Для получения ключа:\n"
        "1️⃣ Подпишись на каналы:\n"
        "🔹 <a href='https://t.me/Gamesgaben'>Steam Games</a>\n"
        "🔹 <a href='https://t.me/PaJohn66'>PaJohn</a>\n"
        "2️⃣ Нажми кнопку \"Проверить подписку\"."
    )
    await message.answer(text, reply_markup=keyboard)

# Обработчик нажатий на кнопки
@dp.callback_query()
async def handle_callback(callback: types.CallbackQuery):
    user_id = callback.from_user.id
    data = callback.data
    
    if data == "check_sub":
        if await check_subscription(user_id):
            await callback.message.answer("\U0001F389 Подписка подтверждена! Теперь ты можешь получить ключ.")
        else:
            await callback.message.answer("❌ Ты не подписан на все каналы. Подпишись и попробуй снова!")
    
    elif data == "invite_friends":
        referral_link = f"https://t.me/{BOT_USERNAME}?start={user_id}"
        await callback.message.answer(f"📩 Приглашай друзей по этой ссылке: {referral_link}\n🎁 За каждых 5 друзей — бонусный ключ!")
    
    elif data == "my_referrals":
        async with aiosqlite.connect("database.db") as db:
            async with db.execute("SELECT referrals, last_key_date FROM users WHERE user_id = ?", (user_id,)) as cursor:
                result = await cursor.fetchone()
                count = result[0] if result else 0
                last_key_date = result[1] if result else None
        remaining = 5 - (count % 5) if (count % 5) != 0 else 0
        response = f"📊 Ты пригласил {count} друзей! До бонусного ключа осталось {remaining} друзей."
        if last_key_date and last_key_date != "":
            try:
                last_dt = datetime.datetime.strptime(last_key_date, "%Y-%m-%d")
                next_dt = last_dt + datetime.timedelta(days=14)
                now = datetime.datetime.now()
                remaining_time = next_dt - now
                days = remaining_time.days
                hours, rem = divmod(remaining_time.seconds, 3600)
                minutes, _ = divmod(rem, 60)
                response += f"\n⏳ Таймер: {days} дней, {hours} часов, {minutes} минут"
            except Exception as e:
                response += "\nОшибка вычисления таймера"
        await callback.message.answer(response)
    
    elif data == "get_key":
        # Сначала проверяем подписку
        if not await check_subscription(user_id):
            await callback.message.answer("❌ Ты не подписан на все каналы. Подпишись и попробуй снова!")
            return
        async with aiosqlite.connect("database.db") as db:
            async with db.execute("SELECT last_key_date FROM users WHERE user_id = ?", (user_id,)) as cursor:
                row = await cursor.fetchone()
            last_key_date_str = row[0] if row and row[0] != "" else None
            can_get = False
            if not last_key_date_str:
                can_get = True
            else:
                try:
                    last_dt = datetime.datetime.strptime(last_key_date_str, "%Y-%m-%d")
                    now = datetime.datetime.now()
                    if (now - last_dt).days >= 14:
                        can_get = True
                except Exception as e:
                    can_get = True
            if can_get:
                key = await get_key_from_file()
                if key:
                    today = datetime.datetime.now().strftime("%Y-%m-%d")
                    await db.execute("UPDATE users SET last_key_date = ? WHERE user_id = ?", (today, user_id))
                    await db.commit()
                    await callback.message.answer(f"🔑 Твой ключ: {key}")
                else:
                    await callback.message.answer("❌ Ключи закончились, попробуй позже!")
            else:
                await callback.message.answer("⏳ Ты уже получал ключ, подожди 14 дней!")
    
    elif data == "timer":
        async with aiosqlite.connect("database.db") as db:
            async with db.execute("SELECT last_key_date FROM users WHERE user_id = ?", (user_id,)) as cursor:
                row = await cursor.fetchone()
        last_key_date_str = row[0] if row and row[0] != "" else None
        if not last_key_date_str:
            await callback.message.answer("Таймер: 0 дней, 0 часов, 0 минут")
        else:
            try:
                last_dt = datetime.datetime.strptime(last_key_date_str, "%Y-%m-%d")
                next_dt = last_dt + datetime.timedelta(days=14)
                now = datetime.datetime.now()
                if next_dt <= now:
                    await callback.message.answer("Таймер истек. Ты можешь получить ключ!")
                else:
                    remaining_time = next_dt - now
                    days = remaining_time.days
                    hours, rem = divmod(remaining_time.seconds, 3600)
                    minutes, _ = divmod(rem, 60)
                    await callback.message.answer(f"Таймер: {days} дней, {hours} часов, {minutes} минут")
            except Exception as e:
                await callback.message.answer("Ошибка вычисления таймера")

async def main():
    await init_db()
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
