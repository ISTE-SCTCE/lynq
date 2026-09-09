import React from 'react';
import { AuthProvider } from './core/auth-provider';
import { AppRouter } from './core/router';

function App() {
  return (
    <AuthProvider>
      <AppRouter />
    </AuthProvider>
  );
}

export default App;
