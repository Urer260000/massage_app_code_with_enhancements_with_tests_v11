
const request = require('supertest');
const app = require('./index');  // Import your app

describe('POST /register', () => {
  it('should create a new user and return a token', async () => {
    const response = await request(app)
      .post('/register')
      .send({
        username: 'testuser',
        email: 'test@email.com',
        password: 'testpassword'
      });
      
    expect(response.statusCode).toBe(201);
    expect(response.body).toHaveProperty('token');
  });

  // ... Additional test cases, such as handling invalid input, etc.
});
