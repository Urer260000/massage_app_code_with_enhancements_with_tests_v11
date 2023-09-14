const express = require('express');
const jwt = require('jsonwebtoken');
const MongoClient = require('mongodb').MongoClient;
const app = express();
const port = 3000;

let client;

MongoClient.connect("mongodb://localhost:27017/mydatabase", { useUnifiedTopology: true }, async function (err, mongoClient) {
    if (err) {
        console.log("Error occurred while connecting to MongoDB Atlas...\n", err);
    } else {
        client = mongoClient;
        console.log('Connected...');
        db = await client.db();
    }
});

app.use(express.json());

app.post('/register', async (req, res) => {
    const newUser = {
        username: req.body.username,
        email: req.body.email,
        password: req.body.password,
        createdAt: new Date(),
        updatedAt: new Date()
    };
var express = require('express');
var app = express();

// set up rate limiter: maximum of five requests per minute
var RateLimit = require('express-rate-limit');
var limiter = RateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // max 100 requests per windowMs
});

// apply rate limiter to all requests
app.use(limiter);

app.get('/:path', function(req, res) {
  let path = req.params.path;
  if (isValidPath(path))
    res.sendFile(path);
});
    await db.collection('users').insertOne(newUser);

    const token = jwt.sign({ userId: newUser._id }, 'yourSecretKey', { expiresIn: '1h' });
    res.status(201).json({ message: 'User registered successfully', userId: newUser._id, token });
});

app.get('/services', async (req, res) => {
    const services = await db.collection('services').find({}).toArray();
    res.status(200).json({ services });
});

// Add middleware to verify JWT tokens
app.use(verifyToken);

app.get('/protected', async (req, res) => {
    // Only authenticated users can access this route
});

app.listen(port, () => {
    console.log(`Server running on port ${port}`);
});

async function verifyToken(req, res, next) {
    const token = req.header('Authorization');
    if (!token) {
        return res.status(401).json({ message: 'Unauthorized' });
    }

    try {
        const decodedToken = await jwt.verify(token, 'yourSecretKey');
        req.userId = decodedToken.userId;
        next();
    } catch (err) {
        return res.status(401).json({ message: 'Unauthorized' });
    }
}
