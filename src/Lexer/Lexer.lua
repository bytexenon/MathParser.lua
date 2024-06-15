--[[
  Name: Lexer.lua
  Author: ByteXenon [Luna Gilbert]
  Date: 2024-06-14
--]]

--* Dependencies *--
local Helpers = require("Helpers/Helpers")
local TokenFactory = require("Lexer/TokenFactory")

--* Imports *--
local makeTrie                 = Helpers.makeTrie
local stringToTable            = Helpers.stringToTable
local createPatternLookupTable = Helpers.createPatternLookupTable
local inheritModule            = Helpers.inheritModule

local concat = table.concat
local insert = table.insert
local rep = string.rep

local createConstantToken    = TokenFactory.createConstantToken
local createVariableToken    = TokenFactory.createVariableToken
local createParenthesesToken = TokenFactory.createParenthesesToken
local createOperatorToken    = TokenFactory.createOperatorToken
local createCommaToken       = TokenFactory.createCommaToken

--* Constants *--
local ERROR_SEPARATOR = "+------------------------------+"
local DEFAULT_OPERATORS = {"+", "-", "*", "/", "^", "%"}
local DEFAULT_OPERATORS_TRIE, DEFAULT_LONGEST_OPERATOR = makeTrie(DEFAULT_OPERATORS)

local WHITESPACE_LOOKUP              = createPatternLookupTable("%s")
local NUMBER_LOOKUP                  = createPatternLookupTable("%d")
local IDENTIFIER_LOOKUP              = createPatternLookupTable("[a-zA-Z_]")
local HEXADECIMAL_NUMBER_LOOKUP      = createPatternLookupTable("[%da-fA-F]")
local PLUS_MINUS_LOOKUP              = createPatternLookupTable("[+-]")
local SCIENTIFIC_E_LOOKUP            = createPatternLookupTable("[eE]")
local HEXADECIMAL_X_LOOKUP           = createPatternLookupTable("[xX]")
local IDENTIFIER_CONTINUATION_LOOKUP = createPatternLookupTable("[a-zA-Z0-9_]")
local PARENTHESIS_LOOKUP             = createPatternLookupTable("[()]")

--* LexerMethods *--
local LexerMethods = {}

--// PRIVATE METHODS \\--

--/ Helper methods /--

--- Gets the next character from the character stream.
-- @return <String> char The next character.
function LexerMethods:peek()
  return self.charStream[self.curCharPos + 1] or "\0"
end

--- Consumes the next character from the character stream.
-- @param <Number?> n=1 The amount of characters to go ahead.
-- @return <String> char The next character.
function LexerMethods:consume(n)
  local newCurCharPos = self.curCharPos + (n or 1)
  local newCurChar    = self.charStream[newCurCharPos] or "\0"
  self.curCharPos = newCurCharPos
  self.curChar    = newCurChar
  return newCurChar
end

--/ Error handling /--

--- Generates an error message with a pointer to the current character.
-- @param <String> message The error message.
-- @param <Number?> positionAdjustment=0 The position adjustment to apply to the pointer.
-- @return <String> errorMessage The error message with a pointer.
function LexerMethods:generateErrorMessage(message, positionAdjustment)
  local position     = self.curCharPos + (positionAdjustment or 0)
  local pointer      = rep(" ", position - 1) .. "^"
  local errorMessage = "\n" .. concat(self.charStream) .. "\n" .. pointer .. "\n" .. message
  return errorMessage
end

--- Displays the error messages if there are any.
function LexerMethods:displayErrors()
  local errors = self.errors
  if #errors > 0 then
    local errorMessage = concat(errors, "\n" .. ERROR_SEPARATOR)
    error("Lexer errors:" .. "\n" .. ERROR_SEPARATOR .. errorMessage .. "\n" .. ERROR_SEPARATOR)
  end
end

--/ Character checks /--

--- Checks if the given character is a number.
-- @param <String?> char=self.curChar The character to check.
-- @return <Boolean> isNumber Whether the character is a number.
function LexerMethods:isNumber(char)
  local char = (char or self.curChar)
  return NUMBER_LOOKUP[char] or (char == "." and NUMBER_LOOKUP[self:peek()])
end

--/ Token consumers /--

--- Consumes the next hexadecimal number from the character stream.
-- @param <Table> number The number character table to append the next number to.
-- @return <Table> number The parsed hexadecimal number.
function LexerMethods:consumeHexNumber(number)
  insert(number, self:consume()) -- consume the '0'
  local isHex = HEXADECIMAL_NUMBER_LOOKUP[self:peek()]
  if not isHex then
    local generatedErrorMessage = self:generateErrorMessage("Expected a number after the 'x' or 'X'", 1)
    insert(self.errors, generatedErrorMessage)
  end
  repeat
    insert(number, self:consume())
    isHex = HEXADECIMAL_NUMBER_LOOKUP[self:peek()]
  until not isHex
  return number
end

--- Consumes the next floating point number from the character stream.
-- @param <Table> number The number character table to append the next number to.
-- @return <Tabel> number The parsed floating point number.
function LexerMethods:consumeFloatNumber(number)
  insert(number, self:consume()) -- consume the digit before the decimal point
  local isNumber = NUMBER_LOOKUP[self:peek()]
  if not isNumber then
    local generatedErrorMessage = self:generateErrorMessage("Expected a number after the decimal point", 1)
    insert(self.errors, generatedErrorMessage)
  end
  repeat
    insert(number, self:consume())
    isNumber = NUMBER_LOOKUP[self:peek()]
  until not isNumber
  return number
end

--- Consumes the next number in scientific notation from the character stream.
-- @param <Table> number The number character table to append the next number to.
-- @return <Table> number The parsed number in scientific notation
function LexerMethods:consumeScientificNumber(number)
  insert(number, self:consume()) -- consume the digit before the exponent
  -- An optional sign, default: +
  if PLUS_MINUS_LOOKUP[self:peek()] then
    -- consume the exponent sign, and insert the plus/minus sign
    insert(number, self:consume())
  end
  local isNumber = NUMBER_LOOKUP[self:peek()]
  if not isNumber then
    local generatedErrorMessage = self:generateErrorMessage("Expected a number after the exponent sign", 1)
    insert(self.errors, generatedErrorMessage)
  end

  repeat
    insert(number, self:consume())
    isNumber = NUMBER_LOOKUP[self:peek()]
  until not isNumber
  return number
end

--- Consumes the next number from the character stream.
-- @return <String> number The next number.
function LexerMethods:consumeNumber()
  local number = { self.curChar }
  local isFloat = false
  local isScientific = false
  local isHex = false

  -- Check for hexadecimal numbers
  if self.curChar == '0' and HEXADECIMAL_X_LOOKUP[self:peek()] then
    return concat(self:consumeHexNumber(number))
  end

  while NUMBER_LOOKUP[self:peek()] do
    insert(number, self:consume())
  end

  -- Check for floating point numbers
  if self:peek() == "." then
    number = self:consumeFloatNumber(number)
  end

  -- Check for scientific notation
  local nextChar = self:peek()
  if SCIENTIFIC_E_LOOKUP[nextChar] then
    number = self:consumeScientificNumber(number)
  end

  return concat(number)
end

--- Consumes the next identifier from the character stream.
-- @return <String> identifier The next identifier.
function LexerMethods:consumeIdentifier()
  local identifier, identifierLen = {}, 0
  local nextChar
  repeat
    identifierLen = identifierLen + 1
    identifier[identifierLen] = self.curChar
    local nextChar = self:peek()
  until not (IDENTIFIER_CONTINUATION_LOOKUP[nextChar] and self:consume())
  -- Use table.concat instead of the .. operator, because it's faster.
  return concat(identifier)
end

--- Consumes the next constant from the character stream.
-- @return <Table> constantToken The next constant token.
function LexerMethods:consumeConstant()
  -- <number>
  if self:isNumber(self.curChar) then
    local newToken = self:consumeNumber()
    return createConstantToken(self, newToken)
  end

  local errorMessage = self:generateErrorMessage(
    "Invalid character detected: '" .. self.curChar
    .. "'. Expected one of the following: a whitespace, a parenthesis, a comma, an operator, or a number."
  )
  insert(self.errors, errorMessage)
  return
end

--- Consumes the next operator from the character stream.
-- @return <Table> operatorToken The next operator token.
function LexerMethods:consumeOperator()
  local node       = self.operatorsTrie
  local charStream = self.charStream
  local curCharPos = self.curCharPos
  local operator

  -- Trie walker
  local index = 0
  while true do
    -- Use raw charStream instead of methods for optimization
    local character = charStream[curCharPos + index]
    node = node[character] -- Advance to the deeper node
    if not node then break end
    if node.value then
      operator = node.value
    end
    index = index + 1
  end
  if operator then
    self:consume(#operator - 1)
  end

  return operator
end

--- Consumes the next token from the character stream.
-- @return <Table> token The next token.
function LexerMethods:consumeToken()
  local curChar = self.curChar

  if WHITESPACE_LOOKUP[curChar] then
    -- Return nothing, so the token gets ignored and skipped
    return
  elseif PARENTHESIS_LOOKUP[curChar] then
    return createParenthesesToken(self, curChar)
  elseif IDENTIFIER_LOOKUP[curChar] then
    return createVariableToken(self, self:consumeIdentifier())
  elseif curChar == "," then
    return createCommaToken(self)
  else
    local operator = self:consumeOperator()
    if operator then
      return createOperatorToken(self, operator)
    end
    return self:consumeConstant()
  end
end

--- Consumes all the tokens from the character stream.
-- @return <Table> tokens The tokens.
function LexerMethods:consumeTokens()
  local tokens, tokensLen = {}, 0

  -- Optimization to not index the "self" table every iteration
  local curChar = self.curChar
  while curChar ~= "\0" do
    local newToken = self:consumeToken()
    -- Since whitespaces return nothing, we have to check if the token is not nil to insert it.
    if newToken then
      tokensLen = tokensLen + 1
      tokens[tokensLen] = newToken
    end

    curChar = self:consume()
  end

  return tokens
end

--// PUBLIC METHODS \\--

--- Resets the lexer to its initial state.
-- @param <Table> charStream The character stream to reset to.
-- @param <Table?> operators=DEFAULT_OPERATORS The operators to reset to.
function LexerMethods:resetToInitialState(charStream, operators)
  assert(charStream, "No charStream given")

  -- If charStream is a string convert it to a table of characters
  self.charStream = (type(charStream) == "string" and stringToTable(charStream)) or charStream
  self.curChar    = (self.charStream[1]) or "\0"
  self.curCharPos = 1

  self.operatorsTrie = (operators and makeTrie(operators)) or DEFAULT_OPERATORS_TRIE
  self.operators = operators or DEFAULT_OPERATORS
end

--- Runs the lexer.
-- @return <Table> tokens The tokens of the expression.
function LexerMethods:run()
  assert(self.charStream, "No charStream given")
  self.errors = {}
  local tokens = self:consumeTokens()

  self:displayErrors()
  return tokens
end

--* Lexer (Tokenizer) *--
local Lexer = {}

--- @class Creates a new Lexer.
-- @param <String|Table> expression The expression to tokenize.
-- @param <Table?> operators=DEFAULT_OPERATORS The operators to use.
-- @param <Number?> charPos=1 The character position to start at.
-- @return <Table> LexerInstance The Lexer instance.
function Lexer:new(expression, operators, charPos)
  local LexerInstance = {}
  LexerInstance.errors = {}
  if expression then
    LexerInstance.charStream = (type(expression) == "string" and stringToTable(expression)) or expression
    LexerInstance.curChar = (LexerInstance.charStream[charPos or 1]) or "\0"
    LexerInstance.curCharPos = charPos or 1
  end
  local operatorTrie = (operators and makeTrie(operators)) or DEFAULT_OPERATORS_TRIE
  local operators    = operators or DEFAULT_OPERATORS
  LexerInstance.operators = operators
  LexerInstance.operatorsTrie = operatorTrie

  -- Main
  inheritModule("LexerInstance", LexerInstance, "LexerMethods" , LexerMethods)

  return LexerInstance
end

return Lexer