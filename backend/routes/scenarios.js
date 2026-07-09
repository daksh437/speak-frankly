const express = require('express');
const { list, getOne } = require('../controllers/scenarioController');

const router = express.Router();

router.get('/', list);
router.get('/:id', getOne);

module.exports = router;
