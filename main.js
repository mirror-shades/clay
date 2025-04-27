const fs = require("fs");

// this helps track which print statements are being used for what
const printDebug = (...args) => console.log("DEBUG: ", ...args);
const printInspect = (...args) => console.log("INSPECT: ", ...args);
const printError = (...args) => console.log("ERROR: ", ...args);

let variables = new Map();

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
      parsedTokens.push(currentLine);
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

function typeCheck(token) {
  if (token.tokenType === TokenType.Value) {
    if (token.valueType === ValueType.Integer) {
      return "integer";
    }
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

function assignValue(assignmentArray) {
  // The last element is the value to assign
  const value = assignmentArray.pop();

  // The second-to-last element is the identifier
  const identifier = assignmentArray.pop();

  // If there are no groups, assign directly to the identifier
  if (assignmentArray.length === 0) {
    variables.set(identifier, value);
    return;
  }

  // The remaining elements are groups that need to be nested
  const assignmentGroups = assignmentArray;

  // Handle nested groups
  let currentMap = variables;

  // Navigate through the group hierarchy, creating maps as needed
  for (let i = 0; i < assignmentGroups.length; i++) {
    const groupToAssign = assignmentGroups[i];

    // If the group doesn't exist yet, create it as a new Map
    if (
      !currentMap.has(groupToAssign) ||
      !(currentMap.get(groupToAssign) instanceof Map)
    ) {
      currentMap.set(groupToAssign, new Map());
    }

    // Move to the next level of nesting
    currentMap = currentMap.get(groupToAssign);
  }

  // Set the value in the deepest map
  currentMap.set(identifier, value);
}

function interpret(parsedTokens) {
  for (let line of parsedTokens) {
    for (let i = 0; i < line.length; i++) {
      let currentToken = line[i];
      let nextToken = line[i + 1];
      let previousToken = line[i - 1];
      if (currentToken.tokenType === TokenType.Assignment) {
        // assignments
        let groups = buildAssignmentArray(line, i);
        let finalValue = undefined;
        if (nextToken.tokenType === TokenType.Value) {
          // Convert numeric strings to actual numbers
          finalValue = isNumber(nextToken.value)
            ? Number(nextToken.value)
            : nextToken.value;
        } else if (
          nextToken.tokenType === TokenType.Lookup ||
          nextToken.tokenType === TokenType.Group
        ) {
          const lookupPath = buildLookupPathForward(line, i + 1);
          finalValue = getLookupValue(lookupPath);
          groups[groups.length - 1] = finalValue; // Replace the token with the actual value
        }
        assignValue(groups); // groups is an array
      }

      if (currentToken.tokenType === TokenType.Inspect) {
        if (previousToken.tokenType === TokenType.Value) {
          printInspect(previousToken.value);
        } else if (previousToken.tokenType === TokenType.Lookup) {
          // Build a lookup path similar to how we build assignment arrays
          let lookupPath = buildLookupPathBackward(line, i);

          // Get the value from the nested maps
          let result = getLookupValue(lookupPath);

          // Check if the result is a token object
          if (
            result &&
            typeof result === "object" &&
            result.value !== undefined
          ) {
            printInspect(result.value);
          } else {
            printInspect(result);
          }
        }
      }
    }
  }
}

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
  /**
   * Makes a list of groups and the identifier to look up
   * For backward traversal (used in inspections)
   * The last element in the array is the identifier
   * The elements before the identifier are groups in reverse order
   */
  let path = [];

  // Start by capturing the identifier being looked up
  if (line[i - 1].tokenType === TokenType.Lookup) {
    path.push(line[i - 1].value);
  }

  // Work backwards to capture groups connected by arrows
  for (let j = i - 2; j >= 0; j--) {
    if (line[j].tokenType === TokenType.Arrow) {
      path.unshift(line[j - 1].value);
    }
  }

  return path;
}

function getLookupValue(lookupPath) {
  /***
   * this function will return the value and the type of the lookup path
   */

  // The last element is the identifier to look up
  const identifier = lookupPath.pop();

  // The remaining elements are groups that need to be traversed
  const groups = lookupPath;

  // If there are no groups, look up directly in the top-level variables
  if (groups.length === 0) {
    const result = variables.get(identifier);
    return result;
  }

  // Handle nested groups
  let currentMap = variables;

  // Navigate through the group hierarchy
  for (let i = 0; i < groups.length; i++) {
    const group = groups[i];

    // If the group doesn't exist, return undefined
    if (!currentMap.has(group) || !(currentMap.get(group) instanceof Map)) {
      return undefined;
    }

    // Move to the next level of nesting
    currentMap = currentMap.get(group);
  }

  // Get the value from the deepest map
  const result = currentMap.get(identifier);
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
  interpret(parsedTokens);
}

main();
