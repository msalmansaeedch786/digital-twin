import os
os.environ["PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION"] = "python"
import google.generativeai as genai
from dotenv import load_dotenv

load_dotenv()
genai.configure(api_key=os.getenv("GEMINI_API_KEY"))

print("Available Models for generateContent:")
for m in genai.list_models():
    if 'generateContent' in m.supported_generation_methods:
        print(m.name)
