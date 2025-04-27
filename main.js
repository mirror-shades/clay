const fs = require("fs");

// this helps track which print statements are being used for what
const printDebug = (...args) => console.log("DEBUG: ", ...args);
const printError = (...args) => console.log("ERROR: ", ...args);

let variables = new Map();

// Create a class to hold both value and type
class TypedValue {
  constructor(value, valueType) {
    this.value = value;
    this.type = valueType;
  }
}

class Token {
  /***
   * @param {string} value
   * @param {string} tokenType // general type of token for parsing
   * @param {string} valueType // used for type checking
   * @param {number} lineNumber
   * @param {number} tokenNumber
   */
  constructor(value, tokenType, valueType, lineNumber, tokenNumber) {
    this.value = value;
    this.tokenType = tokenType;
    this.valueType = valueType;
    this.lineNumber = lineNumber;
    this.tokenNumber = tokenNumber;
  }
}

let TokenType = {
  Group: "Group",
  Identifier: "Identifier",
  Assignment: "Assignment",
  Lookup: "Lookup",
  Value: "Value",
  EOF: "EOF",
  NewLine: "NewLine",
  Inspect: "Inspect",
  Arrow: "Arrow",
};

let ValueType = {
  String: "String",
  Integer: "Integer",
  Float: "Float",
  Boolean: "Boolean",
  Nothing: "Nothing",
};

function isNumber(value) {
  // Match a string that:
  return /^-?\d+(\.\d+)?$/.test(value);
}

function isFloat(value) {
  return /^-?\d+\.\d+$/.test(value);
}

function isValidIdentifier(value) {
  // Match a string that:
  // 1. Starts with a letter (a-z, A-Z) or underscore
  // 2. Contains only letters, numbers, and underscores
  // 3. Does not start with a number
  return /^[a-zA-Z_][a-zA-Z0-9_]*$/.test(value);
}

function isValidString(value) {
  // Match a string that:
  // 1. Starts with a quote
  // 2. Contains any number of:
  //    - escaped characters (\", \\, \n, etc.)
  //    - or non-quote characters
  // 3. Ends with a quote
  return /^"(?:[^"\\]|\\.)*"$/.test(value);
}

function tokenize(input) {
  let tokens = [];
  let currentToken = "";
  let i = 0;

  while (i < input.length) {
    const char = input[i];

    // Handle whitespace
    if (/\s/.test(char)) {
      if (currentToken) {
        tokens.push(currentToken);
        currentToken = "";
      }

      // Handle newlines separately
      if (char === "\n") {
        tokens.push("\n");
      }

      i++;
      continue;
    }

    // Handle special operators
    if (char === "=" || char === "?") {
      if (currentToken) {
        tokens.push(currentToken);
        currentToken = "";
      }
      tokens.push(char);
      i++;
      continue;
    }

    // Handle arrow operator
    if (char === "-" && i + 1 < input.length && input[i + 1] === ">") {
      if (currentToken) {
        tokens.push(currentToken);
        currentToken = "";
      }
      tokens.push("->");
      i += 2;
      continue;
    }

    // Build current token
    currentToken += char;
    i++;
  }

  // Add the last token if there is one
  if (currentToken) {
    tokens.push(currentToken);
  }

  tokens.push("EOF");
  return tokens;
}

function parse(tokens) {
  let _tokens = tokens;
  let activeToken = undefined;
  let nextToken = undefined;
  let parsedTokens = [];
  let currentLine = [];
  let lineNumber = 1;
  let tokenNumber = 1;
  while (true) {
    activeToken = _tokens.shift();
    let newToken = undefined;
    // check to see if we should stop parsing
    if (activeToken === "EOF") {
      if (currentLine.length > 0) {
        parsedTokens.push(currentLine); // push the last line before breaking
      }
      break;
    }

    // catch newlines and operators
    if (activeToken === "\n") {
      if (currentLine.length > 0) {
        // Only push non-empty lines
        parsedTokens.push(currentLine);
      }
      currentLine = [];
      lineNumber++;
      tokenNumber = 1;
      continue;
    }
    if (activeToken === "?") {
      newToken = createToken(
        activeToken,
        TokenType.Inspect,
        ValueType.Nothing,
        lineNumber,
        tokenNumber
      );
      currentLine.push(newToken);
      tokenNumber++;
      continue;
    }
    if (activeToken === "->") {
      newToken = createToken(
        activeToken,
        TokenType.Arrow,
        ValueType.Nothing,
        lineNumber,
        tokenNumber
      );
      currentLine.push(newToken);
      tokenNumber++;
      continue;
    }
    if (activeToken === "=") {
      newToken = createToken(
        activeToken,
        TokenType.Assignment,
        ValueType.Nothing,
        lineNumber,
        tokenNumber
      );
      currentLine.push(newToken);
      tokenNumber++;
      continue;
    }

    nextToken = _tokens[0];

    if (nextToken === "\n" || nextToken === "EOF" || nextToken === "?") {
      // end of a line, either a lookup or a value to be assigned
      if (isNumber(activeToken))
        if (isFloat(activeToken)) {
          newToken = createToken(
            activeToken,
            TokenType.Value,
            ValueType.Float,
            lineNumber,
            tokenNumber
          );
        } else {
          newToken = createToken(
            activeToken,
            TokenType.Value,
            ValueType.Integer,
            lineNumber,
            tokenNumber
          );
        }
      else if (isValidString(activeToken))
        newToken = createToken(
          activeToken,
          TokenType.Value,
          ValueType.String,
          lineNumber,
          tokenNumber
        );
      else if (isValidIdentifier(activeToken))
        if (activeToken === "true" || activeToken === "false") {
          newToken = createToken(
            activeToken,
            TokenType.Value,
            ValueType.Boolean,
            lineNumber,
            tokenNumber
          );
        } else {
          newToken = createToken(
            activeToken,
            TokenType.Lookup,
            ValueType.Nothing,
            lineNumber,
            tokenNumber
          );
        }
      else {
        printError("Invalid value at ", activeToken);
        throw new Error("Invalid value");
      }
      currentLine.push(newToken);
      continue;
    } else if (nextToken === "->") {
      // group
      newToken = createToken(
        activeToken,
        TokenType.Group,
        ValueType.Nothing,
        lineNumber,
        tokenNumber
      );
    } else if (nextToken === "=") {
      // identifier
      newToken = createToken(
        activeToken,
        TokenType.Identifier,
        ValueType.Nothing,
        lineNumber,
        tokenNumber
      );
    }

    if (newToken === undefined) {
      // catch unrecognized tokens
      printError("Invalid token at line ", lineNumber, " token ", tokenNumber);
      throw new Error("Invalid token");
    }
    currentLine.push(newToken);
    tokenNumber++;
  }
  return parsedTokens;
}

function typeCheck(tokens) {
  for (let token of tokens) {
    printDebug(token);
  }
}

function createToken(value, type, valueType, lineNumber, tokenNumber) {
  return new Token(value, type, valueType, lineNumber, tokenNumber);
}

function buildAssignmentArray(line, i) {
  /***
   * makes the proper array for assignment
   * there will always be at least two elements in the array
   * the second to last element is always the identifier
   * the last element is always the value being assigned
   * the elements in front of the identifier are groups
   * [0] will be the top level group descending
   */
  let nestedGroup = [];

  // Start by capturing the initial identifier
  if (line[i - 1].tokenType === TokenType.Identifier) {
    nestedGroup.push(line[i - 1].value);
  }

  // Work backwards to capture groups connected by arrows
  for (let j = i - 2; j >= 0; j--) {
    if (line[j].tokenType === TokenType.Arrow) {
      // nested group is found
      nestedGroup.unshift(line[j - 1].value);
    }
  }
  nestedGroup.push(line[i + 1]);
  return nestedGroup;
}

// Modify assignValue to store typed values
function assignValue(assignmentArray) {
  const value = assignmentArray.pop();
  const identifier = assignmentArray.pop();

  // Create a TypedValue based on the token's type
  let typedValue;
  if (value.tokenType === TokenType.Value) {
    // Direct value assignment
    const actualValue = isNumber(value.value)
      ? Number(value.value)
      : value.value;
    typedValue = new TypedValue(actualValue, value.valueType);
  } else if (value instanceof TypedValue) {
    // Value from a lookup - already a TypedValue
    typedValue = value;
  } else {
    // Fallback case - shouldn't normally happen
    typedValue = new TypedValue(value, inferType(value));
  }

  if (assignmentArray.length === 0) {
    variables.set(identifier, typedValue);
    return;
  }

  let currentMap = variables;
  for (const group of assignmentArray) {
    if (!currentMap.has(group)) {
      currentMap.set(group, new Map());
    }
    currentMap = currentMap.get(group);
  }
  currentMap.set(identifier, typedValue);
}

// Helper function to infer types for non-token values
function inferType(value) {
  if (typeof value === "string") return ValueType.String;
  if (Number.isInteger(value)) return ValueType.Integer;
  if (typeof value === "number") return ValueType.Float;
  if (typeof value === "boolean") return ValueType.Boolean;
  return ValueType.Nothing;
}

function interpret(parsedTokens) {
  for (let lineNumber = 0; lineNumber < parsedTokens.length; lineNumber++) {
    const line = parsedTokens[lineNumber];

    for (let tokenNumber = 0; tokenNumber < line.length; tokenNumber++) {
      let currentToken = line[tokenNumber];
      let nextToken = line[tokenNumber + 1];
      let previousToken = line[tokenNumber - 1];

      if (currentToken.tokenType === TokenType.Assignment) {
        let groups = buildAssignmentArray(line, tokenNumber);
        let finalValue = undefined;

        if (nextToken.tokenType === TokenType.Value) {
          // Convert numeric strings to actual numbers
          const value = isNumber(nextToken.value)
            ? Number(nextToken.value)
            : nextToken.value;
          finalValue = new TypedValue(value, nextToken.valueType);
        } else if (
          nextToken.tokenType === TokenType.Lookup ||
          nextToken.tokenType === TokenType.Group
        ) {
          const lookupPath = buildLookupPathForward(line, tokenNumber + 1);
          finalValue = getLookupValue(lookupPath);
          groups[groups.length - 1] = finalValue;
        }
        assignValue(groups);
      }

      if (currentToken.tokenType === TokenType.Inspect) {
        const lookupPath = buildLookupPathBackward(line, tokenNumber);
        const fullPath = lookupPath.join("->");
        const result = getLookupValue([...lookupPath]);
        let type = "undefined";
        let value = "undefined";
        if (result) {
          type = result.type;
          value = result.value;
        }
        if (previousToken.tokenType === TokenType.Value) {
          type = previousToken.valueType;
          value = previousToken.value;
        }
        printInspect(
          `[${currentToken.lineNumber}:${currentToken.tokenNumber}]`,
          fullPath || "undefined",
          "::",
          type,
          "=",
          value
        );
      }
    }
  }
}

const printInspect = (...args) => {
  console.log(...args);
};

function buildLookupPathForward(line, startIndex) {
  /**
   * Makes a list of groups and the identifier to look up
   * For forward traversal (used in assignments)
   * The last element in the array is the identifier
   * The elements before the identifier are groups in order
   */
  let path = [];

  // Start with the current token (which should be a Lookup or Group)
  if (
    line[startIndex].tokenType === TokenType.Lookup ||
    line[startIndex].tokenType === TokenType.Group
  ) {
    path.push(line[startIndex].value);
  }

  // Work forwards to capture groups connected by arrows
  for (let j = startIndex + 1; j < line.length; j++) {
    if (line[j].tokenType === TokenType.Arrow && j + 1 < line.length) {
      path.push(line[j + 1].value);
      j++; // Skip the next token since we've processed it
    } else {
      break; // Stop when we hit something that's not part of the path
    }
  }

  return path;
}

function buildLookupPathBackward(line, i) {
  let path = [];

  // Start by capturing the identifier being looked up
  if (line[i - 1].tokenType === TokenType.Lookup) {
    path.push(line[i - 1].value);
  }

  // Work backwards to capture groups connected by arrows
  for (let j = i - 2; j >= 0; j--) {
    if (line[j].tokenType === TokenType.Arrow) {
      if (
        line[j - 1].tokenType === TokenType.Group ||
        line[j - 1].tokenType === TokenType.Lookup
      ) {
        path.unshift(line[j - 1].value);
      }
    }
  }

  // If path has only one element (just the identifier) or is empty
  if (path.length <= 1 && line[i - 1]) {
    path = [line[i - 1].value];
  }

  // Make sure the last element (identifier) is included
  if (line[i - 1] && line[i - 1].tokenType === TokenType.Lookup) {
    if (path[path.length - 1] !== line[i - 1].value) {
      path.push(line[i - 1].value);
    }
  }

  return path;
}

function getLookupValue(lookupPath) {
  const identifier = lookupPath.pop();
  const groups = lookupPath;

  if (groups.length === 0) {
    const result = variables.get(identifier);
    if (result instanceof TypedValue) {
      return result;
    }
    return result;
  }

  let currentMap = variables;
  for (let i = 0; i < groups.length; i++) {
    const group = groups[i];
    if (!currentMap.has(group) || !(currentMap.get(group) instanceof Map)) {
      return undefined;
    }
    currentMap = currentMap.get(group);
  }

  const result = currentMap.get(identifier);
  if (result instanceof TypedValue) {
    return result;
  }
  return result;
}

function main() {
  let debug = false;
  let input = undefined;
  const arg = process.argv;
  if (arg.length < 3) {
    printError("Usage: node main.js [--debug] [--input <file.para>]");
    return;
  }
  for (let i = 2; i < arg.length; i++) {
    if (arg[i] === "--debug") {
      debug = true;
    } else {
      //end of argument must be .para
      if (arg[i].endsWith(".para")) {
        input = fs.readFileSync(arg[i], "utf8");
      }
    }
  }
  if (input === undefined) {
    printError("Usage: node main.js [--debug] [--input <file.para>]");
    return;
  }
  let tokens = tokenize(input);
  if (debug) printDebug(tokens);
  let parsedTokens = parse(tokens);
  if (debug) printDebug(parsedTokens);
  //   let typeCheckedTokens = typeCheck(parsedTokens);
  //   if (debug) printDebug(typeCheckedTokens);
  interpret(parsedTokens);
}

main();
