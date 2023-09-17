require('dotenv').config();
const express = require('express');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const rateLimit = require('express-rate-limit');
const MongoClient = require('mongodb').MongoClient;
const app = express();
const port = 3000;

const jwtSecret = process.env.JWT_SECRET || '9OSyS/zT+ReINiI28SWLB2BgAjrx03gEsqa2BpQpxp8';

let client;

MongoClient.connect("mongodb://localhost:27017/mydatabase", { useUnifiedTopology: true }, async function (err, mongoClient) {
    if (err) {
        console.error("Error occurred while connecting to MongoDB Atlas...\n", err);
        process.exit(1);
    } else {
        client = mongoClient;
        console.log('Connected...');
        db = await client.db();
    }
});

app.use(express.json());

// Apply rate limiting middleware
const apiLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100
});
app.use(apiLimiter);

app.post('/register', async (req, res) => {
    try {
        const hashedPassword = await bcrypt.hash(req.body.password, 10);
        const newUser = {
            username: req.body.username,
            email: req.body.email,
            password: hashedPassword,
            createdAt: new Date(),
            updatedAt: new Date()
        };

        await db.collection('users').insertOne(newUser);

        const token = jwt.sign({ userId: newUser._id }, jwtSecret, { expiresIn: '1h' });
        res.status(201).json({ message: 'User registered successfully', userId: newUser._id, token });
    } catch (err) {
        res.status(500).json({ message: 'An error occurred while registering the user.' });
    }
});

app.get('/services', async (req, res) => {
    try {
        const services = await db.collection('services').find({}).toArray();
        res.status(200).json({ services });
    } catch (err) {
        res.status(500).json({ message: 'An error occurred while fetching services.' });
    }
});

// Add middleware to verify JWT tokens
app.use(verifyToken);

app.get('/protected', async (req, res) => {
    // Only authenticated users can access this route
});

async function verifyToken(req, res, next) {
    const token = req.header('Authorization');
    if (!token) {
        return res.status(401).json({ message: 'Unauthorized' });
    }

    try {
        const decodedToken = await jwt.verify(token, jwtSecret);
        req.userId = decodedToken.userId;
        next();
    } catch (err) {
        return res.status(401).json({ message: 'Unauthorized' });
    }
}

app.listen(port, () => {
    console.log(`Server running on port ${port}`);
});
