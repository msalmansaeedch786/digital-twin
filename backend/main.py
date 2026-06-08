import os
os.environ["PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION"] = "python"
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv

from langchain_groq import ChatGroq
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_community.vectorstores import Chroma
from langchain.prompts import PromptTemplate
from langchain.chains import create_retrieval_chain
from langchain.chains.combine_documents import create_stuff_documents_chain

load_dotenv()

app = FastAPI(title="Digital Twin API", version="1.0")

# Enable CORS for the Next.js frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # For production, change this to your frontend URL
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global variables for AI components
vectorstore = None
retriever = None
rag_chain = None

@app.on_event("startup")
async def startup_event():
    global vectorstore, retriever, rag_chain
    
    if not os.getenv("GROQ_API_KEY"):
        print("WARNING: GROQ_API_KEY not set!")
        return

    try:
        # Load the embeddings and VectorDB
        embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")
        vectorstore = Chroma(persist_directory="./chroma_db", embedding_function=embeddings)
        retriever = vectorstore.as_retriever(search_kwargs={"k": 5}) # Get top 5 relevant chunks
        # Initialize Groq LLM
        llm = ChatGroq(model="llama-3.3-70b-versatile", temperature=0.3, api_key=os.getenv("GROQ_API_KEY"))
        
        # Create the System Prompt for the Persona
        system_prompt = (
            "You are the digital twin of Muhammad Salman, a Senior Infrastructure Consultant and 6x AWS Certified professional. "
            "You must speak entirely in the first person as Muhammad Salman ('I', 'my', 'me'). "
            "You are professional, knowledgeable, highly experienced, and helpful. "
            "Answer the user's questions using the facts provided below. "
            "CRITICAL RULES: "
            "1. NEVER mention 'provided context', 'the text', 'this document', or 'knowledge base'. Just answer naturally. "
            "2. If the provided facts do not contain the answer, simply say 'I don't have experience with that yet' or 'I haven't focused on that in my career so far' instead of referencing your knowledge base or context. "
            "3. Do not make up information about your projects or skills. "
            "4. Keep your answers concise, human-like, and conversational. Use markdown formatting (bullet points, bold text) to make your answers easy to read."
            "\n\n"
            "Facts about Muhammad Salman:\n{context}"
        )
        
        prompt = PromptTemplate.from_template(system_prompt + "\n\nQuestion: {input}\nAnswer:")
        
        # Create the RAG chain
        question_answer_chain = create_stuff_documents_chain(llm, prompt)
        rag_chain = create_retrieval_chain(retriever, question_answer_chain)
        
        print("AI Engine successfully loaded and ready!")
    except Exception as e:
        print(f"Failed to load AI components: {e}")

class ChatRequest(BaseModel):
    message: str

class ChatResponse(BaseModel):
    reply: str

@app.post("/chat", response_model=ChatResponse)
async def chat_endpoint(request: ChatRequest):
    if not rag_chain:
        raise HTTPException(status_code=500, detail="AI Engine not initialized. Did you run the ingest script and set the API key?")
        
    try:
        response = rag_chain.invoke({"input": request.message})
        return ChatResponse(reply=response["answer"])
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    return {"status": "healthy", "ai_loaded": rag_chain is not None}
