package org.perl6.nqp.runtime;
import org.perl6.nqp.sixmodel.*;

/**
 * Object representing a reference to a piece of code (may later become a
 * REPR).
 */
public class CodeRef extends SixModelObject {
	/**
	 * The static data about this code reference.
	 */
	public StaticCodeInfo staticInfo;
	
	/**
	 * The captured outer frame, if any.
	 */
	public CallFrame outer;
	
	/**
	 * Sets up the code-ref data structure.
	 */
	public CodeRef(CompilationUnit compUnit, int idx, String name, String uniqueId,
			String[] iLexicalNames, String[] nLexicalNames,
			String[] sLexicalNames, String[] oLexicalNames) {
		staticInfo = new StaticCodeInfo(compUnit, idx, name,uniqueId,
				iLexicalNames, nLexicalNames, sLexicalNames, oLexicalNames);
	}
}
