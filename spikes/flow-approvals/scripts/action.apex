// Flow approvals spike (M6): invoke one standard Flow-approval action from Apex and
// report exactly what came back. Placeholders: ACTION_NAME, PARAM_1/VALUE_1 ... PARAM_3/VALUE_3
// (an unused pair is left as SKIP=SKIP).
Invocable.Action action = Invocable.Action.createStandardAction('ACTION_NAME');
Map<String, String> params = new Map<String, String>{
    'PARAM_1' => 'VALUE_1',
    'PARAM_2' => 'VALUE_2',
    'PARAM_3' => 'VALUE_3'
};
for (String name : params.keySet()) {
    if (name != 'SKIP') {
        action.setInvocationParameter(name, params.get(name));
    }
}
for (Invocable.Action.Result r : action.invoke()) {
    List<String> errors = new List<String>();
    for (Invocable.Action.Error e : r.getErrors()) {
        errors.add(e.getCode() + ': ' + e.getMessage());
    }
    System.debug(LoggingLevel.ERROR, 'ACTION ACTION_NAME success=' + r.isSuccess() + ' errors=' + errors
        + ' outputs=' + r.getOutputParameters());
}
