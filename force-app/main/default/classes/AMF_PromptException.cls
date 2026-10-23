/**
 * Raised when Einstein could not produce the text an admin assistant action
 * asked for (M15): a rule draft or a health summary.
 *
 * Architecture section: 7 (its M15 note), 11 (security).
 *
 * Its message is written for the administrator who asked, because the agent
 * shows it as it is. Nothing depends on the generation: a draft that cannot be
 * written changes no rule, and a health report that cannot be summarised still
 * has its counted facts.
 */
public class AMF_PromptException extends Exception {
}
