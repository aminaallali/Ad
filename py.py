import requests
from bs4 import BeautifulSoup
from telegram.ext import Updater, CommandHandler

# Create an Updater instance with your bot token
updater = Updater(token='6399081736:AAEietH_LsAD-ecun5z_7tpdlNZHtvC0z_Y', use_context=True)

# Define a command handler for your bot
def send_ad(update, context):
    chat_id = update.effective_chat.id
    try:
        # Get the Adsterra website content
        response = requests.get('https://www.adsterra.com/')
        soup = BeautifulSoup(response.text, 'html.parser')

        # Extract the iframe tag
        iframe_tag = soup.find('iframe', {'id': 'adsterra-banner-iframe'})

        # Add your script tag as a src attribute to the iframe tag
        iframe_tag['src'] = "//www.profitablecreativeformat.com/943b83cf68b5827f3584110a40cda053/invoke.js"

        # Send the ad message with the iframe tag
        context.bot.send_message(chat_id=chat_id, text=str(iframe_tag))

        # Log the success
        print(f"Sent ad message to chat {chat_id}")
    except Exception as e:
        # Handle the exception
        print(f"Failed to send ad message to chat {chat_id}: {e}")
        # Send an error message
        context.bot.send_message(chat_id=chat_id, text="Sorry, something went wrong. Please try again later.")

# Register the command handler with the dispatcher
dispatcher = updater.dispatcher
dispatcher.add_handler(CommandHandler('ad', send_ad))

# Start the bot
updater.start_polling()
