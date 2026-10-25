const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    moduleNameMapper: {
        // sfdx-lwc-jest ships no lightning/modal stub; see jest-mocks/lightning/modal.js.
        '^lightning/modal$': '<rootDir>/jest-mocks/lightning/modal'
    }
};
