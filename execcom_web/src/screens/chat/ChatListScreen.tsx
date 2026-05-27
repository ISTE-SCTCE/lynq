import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { MessageSquare, Users, Search, ArrowLeft, Clock, ShieldCheck } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

export const ChatListScreen: React.FC = () => {
  const navigate = useNavigate();
  const { currentUser } = useAuth();
  
  const [activeTab, setActiveTab] = useState<'chats' | 'contacts'>('chats');
  const [chats, setChats] = useState<any[]>([]);
  const [contacts, setContacts] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');

  const loadData = async () => {
    if (!currentUser) return;
    try {
      // 1. Fetch conversations from recent_chats view
      const { data: recentData, error: recentError } = await supabase
        .from('recent_chats')
        .select()
        .or(`sender_id.eq.${currentUser.id},receiver_id.eq.${currentUser.id}`)
        .order('last_message_time', { ascending: false });

      if (recentError) {
        console.error('Error fetching recent chats:', recentError);
      }

      // 2. Fetch contacts (all users except current user)
      const { data: usersData, error: usersError } = await supabase
        .from('users')
        .select('id, name, role, post, email')
        .neq('id', currentUser.id)
        .order('name');

      if (usersError) throw usersError;

      const loadedContacts = usersData || [];
      setContacts(loadedContacts);

      // Map recent chats and filter for direct chats
      const allRecent = (recentData || []).map((c: any) => {
        // Resolve other user's ID
        const otherUserId = c.sender_id === currentUser.id ? c.receiver_id : c.sender_id;
        const otherUser = loadedContacts.find((u: any) => u.id === otherUserId) || {
          id: otherUserId,
          name: c.sender_name || 'Unknown',
          role: 'Member'
        };

        return {
          ...c,
          otherUserId,
          otherUser
        };
      });

      // Keep only DMs (where folder_id is null)
      const dms = allRecent.filter((c: any) => !c.folder_id && c.otherUserId);
      setChats(dms);
    } catch (e) {
      console.error('Error loading chat list:', e);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadData();

    // Subscribe to messages changes to update list in real-time
    const channel = supabase
      .channel('chat_list_changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'messages' }, () => {
        loadData();
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [currentUser]);

  if (!currentUser) return null;

  const filteredChats = searchQuery.trim() === ''
    ? chats
    : chats.filter(c => c.otherUser?.name?.toLowerCase().includes(searchQuery.toLowerCase()));

  const filteredContacts = searchQuery.trim() === ''
    ? contacts
    : contacts.filter(c => c.name?.toLowerCase().includes(searchQuery.toLowerCase()));

  const formatMessageTime = (timeStr?: string) => {
    if (!timeStr) return '';
    const date = new Date(timeStr);
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  };

  return (
    <div className="chat-portal-layout">
      {/* Left Pane: Conversations & Contacts List */}
      <div className="chat-split-left">
        <header className="page-header">
          <button onClick={() => navigate('/home')} className="back-button">
            <ArrowLeft size={20} />
          </button>
          <h2 className="page-title">Messages</h2>
          <div style={{ width: '20px' }}></div>
        </header>

        {/* Tabs */}
        <div className="chat-tabs flex-center">
          <button 
            onClick={() => setActiveTab('chats')} 
            className={`chat-tab-btn flex-center ${activeTab === 'chats' ? 'active' : ''}`}
          >
            <MessageSquare size={16} style={{ marginRight: '6px' }} />
            Chats
          </button>
          <button 
            onClick={() => setActiveTab('contacts')} 
            className={`chat-tab-btn flex-center ${activeTab === 'contacts' ? 'active' : ''}`}
          >
            <Users size={16} style={{ marginRight: '6px' }} />
            Contacts
          </button>
        </div>

        {/* Search Bar */}
        <div className="search-bar-wrapper flex-center" style={{ margin: '14px 0' }}>
          <Search size={16} className="search-icon" />
          <input 
            type="text" 
            placeholder={activeTab === 'chats' ? 'Search conversations...' : 'Search contacts...'}
            className="chat-search-input"
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
          />
        </div>

        {/* Loading / Empty / Data Flow */}
        <div className="chat-scrollable-content">
          {isLoading ? (
            <div className="chat-loading flex-center" style={{ height: '200px' }}>
              <div className="spinner"></div>
            </div>
          ) : activeTab === 'chats' ? (
            filteredChats.length === 0 ? (
              <div className="chat-empty flex-center" style={{ flexDirection: 'column', height: '250px' }}>
                <MessageSquare size={48} style={{ color: 'var(--text-muted)', marginBottom: '12px' }} />
                <span style={{ color: 'var(--text-muted)', fontSize: '13px' }}>No conversations yet.</span>
                <button onClick={() => setActiveTab('contacts')} className="start-msg-btn">Start Messaging</button>
              </div>
            ) : (
              <div className="chat-threads-flow">
                {filteredChats.map((chat: any) => {
                  const hasUnread = chat.unread_count > 0 && chat.last_message_sender_id !== currentUser.id;
                  
                  return (
                    <div 
                      key={chat.conversation_id} 
                      className="chat-thread-row flex-center"
                      onClick={() => navigate(`/chat/${chat.otherUserId}`)}
                    >
                      <div className="avatar-holder flex-center">
                        {chat.otherUser?.name?.[0]?.toUpperCase()}
                      </div>
                      <div className="thread-details">
                        <div className="flex-row-between">
                          <span className="contact-name">{chat.otherUser?.name}</span>
                          <span className={`msg-time ${hasUnread ? 'unread' : ''}`}>
                            {formatMessageTime(chat.last_message_time)}
                          </span>
                        </div>
                        <div className="flex-row-between" style={{ marginTop: '2px' }}>
                          <p className="last-msg-snippet">
                            {chat.is_deleted ? '🚫 Message unsent' : chat.last_message}
                          </p>
                          {hasUnread && (
                            <span className="unread-badge flex-center">
                              {chat.unread_count}
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )
          ) : (
            filteredContacts.length === 0 ? (
              <div className="chat-empty flex-center" style={{ height: '200px', color: 'var(--text-muted)' }}>
                No contacts found.
              </div>
            ) : (
              <div className="contacts-flow">
                {filteredContacts.map((contact: any) => (
                  <div 
                    key={contact.id} 
                    className="contact-row flex-center"
                    onClick={() => navigate(`/chat/${contact.id}`)}
                  >
                    <div className="avatar-holder flex-center contact">
                      {contact.name?.[0]?.toUpperCase()}
                    </div>
                    <div className="contact-info">
                      <span className="contact-name">{contact.name}</span>
                      <span className="contact-subtitle">{contact.post || contact.role}</span>
                    </div>
                  </div>
                ))}
              </div>
            )
          )}
        </div>
      </div>

      {/* Right Pane: Premium Desktop Welcome panel */}
      <div className="chat-split-right">
        <div className="chat-desktop-welcome flex-center">
          <div className="ambient-spotlight"></div>
          <GlassCard className="welcome-card-glass float-animation" padding="48px">
            <div className="welcome-icon-aura flex-center">
              <MessageSquare size={38} style={{ color: 'rgb(22, 192, 122)' }} />
            </div>
            <h3 className="welcome-card-title">LYNQ Secure Chat</h3>
            <p className="welcome-card-desc">
              Select an organizer or committee colleague on the left column to begin real-time, end-to-end encrypted direct messaging.
            </p>
            <div className="security-badge-row flex-center">
              <div className="sec-tag flex-center">
                <ShieldCheck size={14} style={{ color: 'rgb(22, 192, 122)', marginRight: '6px' }} />
                <span>Supabase Channels Enabled</span>
              </div>
            </div>
          </GlassCard>
        </div>
      </div>

      <NavBar />

      <style>{`
        /* Split-Pane Portal Layout */
        .chat-portal-layout {
          width: 100%;
          display: flex;
          flex-direction: column;
          padding: 16px 20px;
          min-height: 100vh;
        }

        .chat-split-left {
          width: 100%;
          display: flex;
          flex-direction: column;
        }

        .chat-split-right {
          display: none; /* Hidden on mobile */
        }

        .chat-scrollable-content {
          flex: 1;
          overflow-y: auto;
        }

        @media (min-width: 1024px) {
          .chat-portal-layout {
            display: flex;
            flex-direction: row;
            height: calc(100vh - 40px);
            gap: 24px;
            padding-bottom: 20px;
            box-sizing: border-box;
          }

          .chat-split-left {
            width: 380px;
            flex-shrink: 0;
            display: flex;
            flex-direction: column;
            background: var(--bg-secondary);
            border: 1px solid var(--border-light);
            border-radius: 24px;
            padding: 24px;
            overflow: hidden;
            box-shadow: var(--shadow-premium);
          }

          .chat-split-right {
            display: flex;
            flex: 1;
            flex-direction: column;
            background: var(--bg-secondary);
            border: 1px solid var(--border-light);
            border-radius: 24px;
            overflow: hidden;
            position: relative;
            box-shadow: var(--shadow-premium);
          }

          .chat-scrollable-content {
            margin-top: 10px;
            padding-right: 4px;
          }
        }

        .page-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: 60px;
          flex-shrink: 0;
        }

        .back-button {
          color: var(--text-primary);
        }

        .page-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          color: var(--text-primary);
        }

        /* Tabs styling */
        .chat-tabs {
          background: rgba(255,255,255,0.03);
          border: 1px solid var(--border-light);
          padding: 4px;
          border-radius: 12px;
          margin-top: 10px;
          flex-shrink: 0;
        }

        .chat-tab-btn {
          flex: 1;
          padding: 10px;
          border: none;
          background: transparent;
          border-radius: 8px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
          color: var(--text-muted);
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .chat-tab-btn.active {
          background: rgba(22, 192, 122, 0.15);
          color: rgb(22, 192, 122);
        }

        /* Search bar */
        .search-bar-wrapper {
          background: rgba(255,255,255,0.02);
          border: 1px solid var(--border-light);
          border-radius: 12px;
          padding: 10px 16px;
          width: 100%;
          flex-shrink: 0;
        }

        .search-icon {
          color: var(--text-muted);
          margin-right: 10px;
        }

        .chat-search-input {
          background: transparent;
          border: none;
          outline: none;
          color: var(--text-primary);
          font-family: var(--font-inter);
          font-size: 13.5px;
          width: 100%;
        }

        .start-msg-btn {
          margin-top: 14px;
          background: rgb(22, 192, 122);
          color: #fff;
          border: none;
          border-radius: 8px;
          padding: 8px 16px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 12.5px;
          cursor: pointer;
        }

        /* Threads flow */
        .chat-threads-flow, .contacts-flow {
          display: flex;
          flex-direction: column;
          gap: 8px;
          margin-top: 6px;
        }

        .chat-thread-row, .contact-row {
          padding: 14px;
          border-radius: 16px;
          background: rgba(255,255,255,0.015);
          border: 1px solid var(--border-light);
          cursor: pointer;
          transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
          justify-content: flex-start;
        }

        .chat-thread-row:hover, .contact-row:hover {
          background: rgba(255,255,255,0.04);
          transform: translateY(-2px);
          box-shadow: 0 4px 15px rgba(0,0,0,0.03);
        }

        .avatar-holder {
          width: 46px;
          height: 46px;
          border-radius: 50%;
          background: rgba(22, 192, 122, 0.12);
          color: rgb(22, 192, 122);
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 18px;
          flex-shrink: 0;
        }

        .avatar-holder.contact {
          background: rgba(255,255,255,0.04);
          color: var(--text-secondary);
        }

        .thread-details {
          flex: 1;
          margin-left: 14px;
          display: flex;
          flex-direction: column;
        }

        .contact-info {
          margin-left: 14px;
          display: flex;
          flex-direction: column;
          gap: 2px;
        }

        .contact-name {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 15px;
          color: var(--text-primary);
        }

        .flex-row-between {
          display: flex;
          justify-content: space-between;
          align-items: center;
          width: 100%;
        }

        .msg-time {
          font-size: 11px;
          color: var(--text-muted);
        }

        .msg-time.unread {
          color: rgb(22, 192, 122);
          font-weight: 700;
        }

        .last-msg-snippet {
          font-size: 13px;
          color: var(--text-secondary);
          margin: 0;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          max-width: 160px;
        }

        @media (min-width: 1024px) {
          .last-msg-snippet {
            max-width: 220px;
          }
        }

        .unread-badge {
          background: rgb(22, 192, 122);
          color: #fff;
          border-radius: 50%;
          width: 18px;
          height: 18px;
          font-size: 9.5px;
          font-weight: 800;
          flex-shrink: 0;
        }

        .contact-subtitle {
          font-size: 12.5px;
          color: var(--text-muted);
        }

        /* Desktop Welcome Pane */
        .chat-desktop-welcome {
          width: 100%;
          height: 100%;
          flex-direction: column;
          position: relative;
          background: radial-gradient(circle at center, rgba(22, 192, 122, 0.03) 0%, transparent 70%);
          padding: 40px;
          box-sizing: border-box;
        }

        .ambient-spotlight {
          position: absolute;
          width: 400px;
          height: 400px;
          border-radius: 50%;
          background: radial-gradient(circle, rgba(22, 192, 122, 0.06) 0%, transparent 70%);
          top: 20%;
          left: 30%;
          pointer-events: none;
        }

        .welcome-card-glass {
          max-width: 440px;
          text-align: center;
          background: rgba(255, 255, 255, 0.02);
          border: 1px solid var(--border-glass);
          box-shadow: var(--shadow-premium);
          border-radius: 32px;
          z-index: 1;
        }

        .welcome-icon-aura {
          width: 76px;
          height: 76px;
          border-radius: 24px;
          background: rgba(22, 192, 122, 0.08);
          border: 1px solid rgba(22, 192, 122, 0.25);
          margin: 0 auto 24px auto;
          box-shadow: 0 10px 25px rgba(22, 192, 122, 0.15);
        }

        .welcome-card-title {
          font-family: var(--font-space-grotesk);
          font-size: 24px;
          font-weight: 800;
          color: var(--text-primary);
          margin-bottom: 12px;
          letter-spacing: -0.5px;
        }

        .welcome-card-desc {
          font-size: 14px;
          color: var(--text-secondary);
          line-height: 1.6;
          margin-bottom: 28px;
        }

        .security-badge-row {
          width: 100%;
        }

        .sec-tag {
          background: rgba(22, 192, 122, 0.06);
          border: 1px solid rgba(22, 192, 122, 0.15);
          border-radius: 12px;
          padding: 8px 16px;
          font-size: 12px;
          font-weight: 600;
          color: var(--text-secondary);
        }
      `}</style>
    </div>
  );
};
