const express = require('express');
const { define } = require('../controllers/dictionaryController');

const router = express.Router();

// Public: dictionary lookups are free and unmetered (cheap, cached, upstream is free).
router.get('/:word', define);

module.exports = router;
