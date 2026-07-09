/** Scenario library endpoints. Public content — no AI, no auth needed. */
const { listScenarios, getScenario } = require('../services/scenarioData');

function list(req, res) {
  const level = (req.query.level || '').toString().trim();
  const theme = (req.query.theme || '').toString().trim();
  let items = listScenarios();
  if (level) items = items.filter((s) => s.level === level);
  if (theme) items = items.filter((s) => s.theme === theme);
  return res.json({ success: true, data: items });
}

function getOne(req, res) {
  const scenario = getScenario(req.params.id);
  if (!scenario) return res.status(404).json({ success: false, error: 'SCENARIO_NOT_FOUND' });
  const { setup, ...pub } = scenario; // hide internal system-prompt setup
  return res.json({ success: true, data: pub });
}

module.exports = { list, getOne };
