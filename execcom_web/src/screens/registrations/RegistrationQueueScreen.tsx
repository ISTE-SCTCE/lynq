import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Inbox, Check, X, ShieldAlert, BadgeInfo, Calendar, CreditCard, HelpCircle, Phone, Mail, Award, CheckCircle2, RefreshCw } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';
import { PrimaryButton } from '../../shared/components/PrimaryButton';
import { NavBar } from '../../shared/components/NavBar';

const CACHED_EXCEL_DATA = [
  {"Timestamp":"2026-04-09T06:21:00.000Z","Name":"Gayathri AS ","DOB":"2007-02-09T18:30:00.000Z","Year":1,"Branch":"Electronics and Communication","Phone":9539338741,"Email":"asgayathri48@gmail.com","Membership":649,"TransactionID":1604247191,"Forum":"None Selected"},
  {"Timestamp":"2026-04-11T08:15:15.000Z","Name":"Parthasarathy","DOB":"2005-06-05T18:30:00.000Z","Year":2,"Branch":"Mechanical Engineering","Phone":8590467936,"Email":"parthasarathy03062005@gmail.com","Membership":649,"TransactionID":61013161514,"Forum":"None Selected"},
  {"Timestamp":"2026-04-11T16:43:52.000Z","Name":"Viswajith S S","DOB":"2006-08-17T18:30:00.000Z","Year":2,"Branch":"Electronics and Communication","Phone":6238969245,"Email":"viswajithss18@gmail.com","Membership":1199,"TransactionID":"CICAgNicmPmZBA","Forum":"EXIS Forum (149)"},
  {"Timestamp":"2026-04-12T04:30:10.000Z","Name":"Sreeram PS","DOB":"2006-09-15T18:30:00.000Z","Year":1,"Branch":"Electronics and Communication","Phone":8848360097,"Email":"sreeramps1609@gmail.com","Membership":649,"TransactionID":646857101286,"Forum":"EXIS Forum (149)"},
  {"Timestamp":"2026-04-17T12:31:13.000Z","Name":"Ganesh G","DOB":"2006-05-30T18:30:00.000Z","Year":2,"Branch":"Computer Science","Phone":9446967119,"Email":"ganeshgopal3106@gmail.com","Membership":649,"TransactionID":610751875169,"Forum":"BITS Forum (129)"},
  {"Timestamp":"2026-04-18T11:12:25.000Z","Name":"ABHINANTH S NATH","DOB":"2006-03-27T18:30:00.000Z","Year":2,"Branch":"Electronics and Communication","Phone":7012826799,"Email":"abinanth@gmail.com","Membership":649,"TransactionID":646583738939,"Forum":"None Selected"},
  {"Timestamp":"2026-04-18T11:14:43.000Z","Name":"CHINAMAYI","DOB":"2006-03-27T18:30:00.000Z","Year":2,"Branch":"Computer Science","Phone":9567440301,"Email":"chinmayi@gmail.com","Membership":649,"TransactionID":610126297897,"Forum":"None Selected"},
  {"Timestamp":"2026-04-21T05:32:42.000Z","Name":"ADARSH P VINOD","DOB":"2006-01-27T18:30:00.000Z","Year":2,"Branch":"Computer Science","Phone":8547313055,"Email":"adarshcr4@gmail.com","Membership":1199,"TransactionID":611163459768,"Forum":"SWaS Forum (299)"},
  {"Timestamp":"2026-04-22T16:02:51.000Z","Name":"Manupriya prasad ","DOB":"2007-04-17T18:30:00.000Z","Year":1,"Branch":"Mechanical and Automobile Engineering","Phone":8075619064,"Email":"manupriyaa7prasad@gmail.com","Membership":1499,"TransactionID":611283130594,"Forum":"SWaS Forum (299), TORQ Forum (129)"},
  {"Timestamp":"2026-04-23T03:36:20.000Z","Name":"Arjun S","DOB":"2006-12-17T18:30:00.000Z","Year":2,"Branch":"Mechanical Engineering","Phone":9947584831,"Email":"arjuns8267@gmail.com","Membership":649,"TransactionID":90602688981,"Forum":"TORQ Forum (129)"},
  {"Timestamp":"2026-04-23T07:34:32.000Z","Name":"MOHAMMED FARHAN","DOB":"2006-07-26T18:30:00.000Z","Year":2,"Branch":"Mechanical and Automobile Engineering","Phone":7907726056,"Email":"farhanmohammed2706@gmail.com","Membership":649,"TransactionID":611309859624,"Forum":"None Selected"},
  {"Timestamp":"2026-04-23T08:13:56.000Z","Name":"Joneth Jills","DOB":"2006-05-29T18:30:00.000Z","Year":2,"Branch":"Mechanical and Automobile Engineering","Phone":8848615115,"Email":"jonethjillsff@gmail.com","Membership":649,"TransactionID":647975757708,"Forum":"None Selected"},
  {"Timestamp":"2026-04-23T15:52:56.000Z","Name":"THANU SREE N","DOB":"2006-08-14T18:30:00.000Z","Year":2,"Branch":"Mechanical and Automobile Engineering","Phone":7306961915,"Email":"thanusreenubi@gmail.com","Membership":649,"TransactionID":611347302744,"Forum":"None Selected"},
  {"Timestamp":"2026-05-06T09:47:29.000Z","Name":"Thejas Krishna","DOB":"2006-12-04T18:30:00.000Z","Year":2,"Branch":"Computer Science","Phone":8129047109,"Email":"thejask9495@gmail.com","Membership":649,"TransactionID":612601555589,"Forum":"None Selected"},
  {"Timestamp":"2026-05-13T05:33:59.000Z","Name":"Ashishna Shahul S ","DOB":"2005-11-24T18:30:00.000Z","Year":2,"Branch":"Computer Science","Phone":6374128384,"Email":"ars.suru786@gmail.com","Membership":1199,"TransactionID":613354433613,"Forum":"SWaS Forum (299), BITS Forum (129)"}
];

export const RegistrationQueueScreen: React.FC = () => {
  const navigate = useNavigate();
  const { currentUser, permissions } = useAuth();
  
  const [activeTab, setActiveTab] = useState<'Pending' | 'Payment' | 'Approved' | 'Rejected' | 'Excel Intake'>('Pending');
  const [queue, setQueue] = useState<any[]>([]);
  const [excelQueue, setExcelQueue] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  
  // Details Modal
  const [selectedReg, setSelectedReg] = useState<any | null>(null);
  const [isActioning, setIsActioning] = useState(false);

  const loadQueue = async () => {
    setIsLoading(true);
    try {
      // 1. Fetch live queue from Supabase
      const { data, error } = await supabase
        .from('registration_queue')
        .select()
        .order('created_at', { ascending: false });

      if (error) throw error;
      setQueue(data || []);

      // 2. Fetch live data from Google Sheets Macro
      try {
        const sheetRes = await fetch('https://script.google.com/macros/s/AKfycbwSaurzyOEbeJoKTVgCqVhy-esPWq2HpU6UOtfK_7Ds5p7Kisz736_m2k6UnwnWP2Jg/exec');
        if (sheetRes.ok) {
          const sheetData = await sheetRes.json();
          if (Array.isArray(sheetData)) {
            const mapped = sheetData.map((item: any, idx: number) => ({
              id: 9000 + idx, // Keep distinct from Supabase
              name: item.Name?.trim() || 'No Name',
              email: item.Email?.trim() || '',
              phone: item.Phone ? String(item.Phone) : '',
              branch: item.Branch || '',
              year: item.Year ? String(item.Year) : '',
              dob: item.DOB || '',
              membership_type: `₹${item["Membership "] || item.Membership || '649'} (${item.Forum || 'None'})`,
              payment_status: 'paid',
              roll_number: String(item.TransactionID || ''),
              source: 'Google Sheet Excel',
              status: 'excel_intake',
              created_at: item.Timestamp || new Date().toISOString(),
              raw_forum: item.Forum || 'None Selected',
              raw_membership: String(item["Membership "] || item.Membership || '649')
            }));
            setExcelQueue(mapped);
            return;
          }
        }
        throw new Error("Fetch failed");
      } catch (sheetErr) {
        console.log("Sheet fetch timed out or CORS restricted, loading pre-populated Excel cached records:", sheetErr);
        const mappedFallback = CACHED_EXCEL_DATA.map((item: any, idx: number) => ({
          id: 9000 + idx,
          name: item.Name?.trim() || 'No Name',
          email: item.Email?.trim() || '',
          phone: item.Phone ? String(item.Phone) : '',
          branch: item.Branch || '',
          year: item.Year ? String(item.Year) : '',
          dob: item.DOB || '',
          membership_type: `₹${item.Membership || '649'} (${item.Forum || 'None'})`,
          payment_status: 'paid',
          roll_number: String(item.TransactionID || ''),
          source: 'Google Sheet Excel',
          status: 'excel_intake',
          created_at: item.Timestamp || new Date().toISOString(),
          raw_forum: item.Forum || 'None Selected',
          raw_membership: String(item.Membership || '649')
        }));
        setExcelQueue(mappedFallback);
      }
    } catch (e: any) {
      console.error('Error loading registration queue:', e);
      alert('Failed to load queue: ' + e.message);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadQueue();

    // Subscribe to queue changes
    const channel = supabase
      .channel('registration_queue_changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'registration_queue' }, () => {
        loadQueue();
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, []);

  if (!currentUser || !permissions) return null;

  const isAllowed = permissions.role >= 5; // viceChairman or chairman
  
  if (!isAllowed) {
    return (
      <div className="access-denied flex-center" style={{ height: '100vh', flexDirection: 'column', padding: '24px', textAlign: 'center' }}>
        <ShieldAlert size={64} style={{ color: 'var(--accent-red)', marginBottom: '16px' }} />
        <h2 style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: '800' }}>Access Denied</h2>
        <p style={{ color: 'var(--text-muted)', fontSize: '14px', maxWidth: '350px', margin: '8px 0 24px 0' }}>
          Only the Vice Chairman or Chairman hold administrative credentials to review pending registration applicant lists.
        </p>
        <button onClick={() => navigate(-1)} className="back-btn-secondary">Go Back</button>
      </div>
    );
  }

  const getFilteredItems = () => {
    switch (activeTab) {
      case 'Payment':
        return queue.filter(r => r.status === 'payment_pending');
      case 'Approved':
        return queue.filter(r => r.status === 'approved');
      case 'Rejected':
        return queue.filter(r => r.status === 'rejected');
      case 'Excel Intake':
        return excelQueue;
      default:
        return queue.filter(r => r.status === 'pending');
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'approved': return '#16c07a';
      case 'rejected': return '#ef4444';
      case 'payment_pending': return '#f59e0b';
      case 'excel_intake': return '#0284c7';
      default: return '#268aff';
    }
  };

  const handleQueueAction = async (regId: number, status: string) => {
    setIsActioning(true);
    try {
      const { error } = await supabase
        .from('registration_queue')
        .update({
          status: status,
          reviewed_by: currentUser.id,
          reviewed_at: new Date().toISOString()
        })
        .eq('id', regId);

      if (error) throw error;
      
      setSelectedReg(null);
      loadQueue();
    } catch (e: any) {
      alert('Action failed: ' + e.message);
    } finally {
      setIsActioning(false);
    }
  };

  const handleApproveExcelIntake = async (item: any) => {
    setIsActioning(true);
    try {
      let plan = '1 Year';
      if (item.raw_membership === '1199') plan = '2 Year';
      else if (item.raw_membership === '1499') plan = '3 Year';

      let forum = null;
      if (item.raw_forum && item.raw_forum !== 'None Selected' && item.raw_forum !== 'None') {
        const cleanForum = item.raw_forum.split(' ')[0];
        forum = cleanForum || item.raw_forum;
      }

      const response = await supabase.functions.invoke('admin-create-user', {
        body: {
          name: item.name,
          email: item.email,
          role: 'member',
          phone: item.phone,
          roll_number: item.roll_number,
          branch: item.branch,
          membership_plan: plan,
          forum: forum,
          status: 'active',
        },
      });

      if (response.error) {
        throw new Error(response.error.message || 'Failed to enroll member via admin-create-user.');
      }

      const { error: queueError } = await supabase
        .from('registration_queue')
        .insert({
          name: item.name,
          email: item.email,
          phone: item.phone,
          branch: item.branch,
          year: item.year,
          membership_type: item.membership_type,
          payment_status: 'paid',
          roll_number: item.roll_number,
          source: 'Google Sheet Excel',
          status: 'approved',
          reviewed_by: currentUser.id,
          reviewed_at: new Date().toISOString(),
          created_at: item.created_at
        });

      if (queueError) {
        console.error('Queue history insertion failed:', queueError);
      }

      alert(`Member "${item.name}" has been successfully imported and approved!`);
      setSelectedReg(null);
      loadQueue();
    } catch (e: any) {
      console.error('Approval failed:', e);
      alert('Approval failed: ' + e.message);
    } finally {
      setIsActioning(false);
    }
  };

  const filtered = getFilteredItems();
  const counts: Record<string, number> = {
    Pending: queue.filter(r => r.status === 'pending').length,
    Payment: queue.filter(r => r.status === 'payment_pending').length,
    Approved: queue.filter(r => r.status === 'approved').length,
    Rejected: queue.filter(r => r.status === 'rejected').length,
    'Excel Intake': excelQueue.length
  };

  return (
    <div className="queue-container" style={{ paddingBottom: '80px' }}>
      <header className="page-header flex-center" style={{ justifyContent: 'space-between' }}>
        <button onClick={() => navigate('/home')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Registration Queue</h2>
        <button onClick={loadQueue} className="back-button">
          <RefreshCw size={18} />
        </button>
      </header>

      {/* Tabs */}
      <div className="queue-tabs flex-center">
        {['Pending', 'Payment', 'Approved', 'Rejected', 'Excel Intake'].map((tab) => {
          const tabVal = tab as any;
          const count = counts[tabVal] || 0;
          return (
            <button
              key={tab}
              onClick={() => setActiveTab(tabVal)}
              className={`queue-tab-btn flex-center ${activeTab === tab ? 'active' : ''}`}
            >
              {tab} <span className="tab-count-lbl">{count}</span>
            </button>
          );
        })}
      </div>

      {/* Queue items flow */}
      {isLoading ? (
        <div className="queue-loading flex-center" style={{ height: '250px' }}>
          <div className="spinner"></div>
        </div>
      ) : filtered.length === 0 ? (
        <div className="queue-empty flex-center" style={{ flexDirection: 'column', height: '280px' }}>
          <Inbox size={48} style={{ color: 'var(--text-muted)', marginBottom: '12px' }} />
          <span style={{ color: 'var(--text-muted)', fontSize: '13px' }}>No registrations in this queue.</span>
        </div>
      ) : (
        <div className="queue-flow" style={{ marginTop: '16px' }}>
          {filtered.map((item: any) => {
            const statusColor = getStatusColor(item.status);
            return (
              <div 
                key={item.id} 
                className="queue-card-wrapper"
                onClick={() => setSelectedReg(item)}
              >
                <GlassCard className="queue-card" padding="14px" style={{ borderLeft: `4px solid ${statusColor}` }}>
                  <div className="flex-row-between">
                    <div className="queue-info flex-center" style={{ gap: '12px', justifyContent: 'flex-start' }}>
                      <div 
                        className="avatar flex-center"
                        style={{ backgroundColor: `${statusColor}15`, color: statusColor }}
                      >
                        {item.name?.[0]?.toUpperCase()}
                      </div>
                      <div className="text-details" style={{ textAlign: 'left' }}>
                        <span className="applicant-name">{item.name}</span>
                        <span className="applicant-email">{item.email}</span>
                        {item.roll_number && (
                          <span className="applicant-roll">
                            {item.roll_number} {item.branch ? `· ${item.branch}` : ''}
                          </span>
                        )}
                      </div>
                    </div>

                    <div className="status-badge-wrapper" style={{ textAlign: 'right' }}>
                      <span 
                        className="status-pill"
                        style={{ backgroundColor: `${statusColor}18`, color: statusColor, border: `1px solid ${statusColor}35` }}
                      >
                        {item.status.toUpperCase()}
                      </span>
                      {item.created_at && (
                        <span className="date-lbl">
                          {new Date(item.created_at).toLocaleDateString([], { month: 'short', day: 'numeric' })}
                        </span>
                      )}
                    </div>
                  </div>
                </GlassCard>
              </div>
            );
          })}
        </div>
      )}

      {/* Details drawer modal overlay */}
      {selectedReg && (
        <div className="modal-overlay flex-center" onClick={() => setSelectedReg(null)}>
          <GlassCard className="details-drawer" padding="24px" onClick={e => e.stopPropagation()}>
            <div className="modal-header flex-center" style={{ justifyContent: 'space-between', marginBottom: '20px' }}>
              <h3 className="drawer-title" style={{ margin: 0 }}>Applicant details</h3>
              <button className="close-btn" onClick={() => setSelectedReg(null)}>
                <X size={18} />
              </button>
            </div>

            <div className="applicant-profile flex-center" style={{ gap: '14px', justifyContent: 'flex-start', marginBottom: '20px' }}>
              <div 
                className="avatar large flex-center"
                style={{ 
                  backgroundColor: `${getStatusColor(selectedReg.status)}15`, 
                  color: getStatusColor(selectedReg.status),
                  width: '54px',
                  height: '54px',
                  fontSize: '22px'
                }}
              >
                {selectedReg.name?.[0]?.toUpperCase()}
              </div>
              <div className="profile-text" style={{ textAlign: 'left' }}>
                <h4 style={{ fontFamily: 'var(--font-space-grotesk)', fontSize: '18px', fontWeight: '800', margin: 0 }}>
                  {selectedReg.name}
                </h4>
                <span className="status-pill" style={{ display: 'inline-block', marginTop: '4px', backgroundColor: `${getStatusColor(selectedReg.status)}15`, color: getStatusColor(selectedReg.status) }}>
                  {selectedReg.status.toUpperCase()}
                </span>
              </div>
            </div>

            <div className="detail-rows-list">
              <div className="detail-row flex-center">
                <Mail size={16} className="detail-icon" />
                <span className="detail-lbl">Email Address:</span>
                <span className="detail-val">{selectedReg.email}</span>
              </div>
              <div className="detail-row flex-center">
                <Phone size={16} className="detail-icon" />
                <span className="detail-lbl">Phone Contact:</span>
                <span className="detail-val">{selectedReg.phone || '—'}</span>
              </div>
              <div className="detail-row flex-center">
                <BadgeInfo size={16} className="detail-icon" />
                <span className="detail-lbl">Roll Number:</span>
                <span className="detail-val">{selectedReg.roll_number || '—'}</span>
              </div>
              <div className="detail-row flex-center">
                <BadgeInfo size={16} className="detail-icon" />
                <span className="detail-lbl">Course Branch:</span>
                <span className="detail-val">{selectedReg.branch || '—'}</span>
              </div>
              <div className="detail-row flex-center">
                <Calendar size={16} className="detail-icon" />
                <span className="detail-lbl">Admission Year:</span>
                <span className="detail-val">{selectedReg.year || '—'}</span>
              </div>
              <div className="detail-row flex-center">
                <Award size={16} className="detail-icon" />
                <span className="detail-lbl">Membership tier:</span>
                <span className="detail-val" style={{ textTransform: 'capitalize' }}>{selectedReg.membership_type || 'standard'}</span>
              </div>
              <div className="detail-row flex-center">
                <CreditCard size={16} className="detail-icon" />
                <span className="detail-lbl">Payment Status:</span>
                <span className="detail-val" style={{ textTransform: 'capitalize' }}>{selectedReg.payment_status || 'pending'}</span>
              </div>
              <div className="detail-row flex-center">
                <HelpCircle size={16} className="detail-icon" />
                <span className="detail-lbl">Channel Source:</span>
                <span className="detail-val" style={{ textTransform: 'capitalize' }}>{selectedReg.source || 'google_form'}</span>
              </div>
            </div>

            {/* Action buttons */}
            {(selectedReg.status === 'pending' || selectedReg.status === 'payment_pending' || selectedReg.status === 'excel_intake') && (
              <div className="action-buttons-wrapper" style={{ marginTop: '24px' }}>
                {isActioning ? (
                  <div className="flex-center" style={{ padding: '10px 0' }}>
                    <div className="spinner"></div>
                  </div>
                ) : selectedReg.status === 'excel_intake' ? (
                  <button 
                    className="drawer-action-btn approve flex-center"
                    style={{ width: '100%' }}
                    onClick={() => handleApproveExcelIntake(selectedReg)}
                  >
                    <Check size={16} style={{ marginRight: '6px' }} />
                    Import & Approve Member
                  </button>
                ) : (
                  <div className="flex-col" style={{ gap: '10px', display: 'flex' }}>
                    <div className="flex-row-between" style={{ gap: '10px' }}>
                      <button 
                        className="drawer-action-btn reject flex-center"
                        onClick={() => handleQueueAction(selectedReg.id, 'rejected')}
                      >
                        <X size={16} style={{ marginRight: '6px' }} />
                        Reject
                      </button>
                      
                      <button 
                        className="drawer-action-btn approve flex-center"
                        onClick={() => handleQueueAction(selectedReg.id, 'approved')}
                      >
                        <Check size={16} style={{ marginRight: '6px' }} />
                        Approve
                      </button>
                    </div>
                    
                    {selectedReg.status === 'pending' && (
                      <button 
                        className="drawer-action-btn payment flex-center"
                        onClick={() => handleQueueAction(selectedReg.id, 'payment_pending')}
                      >
                        <CreditCard size={16} style={{ marginRight: '6px' }} />
                        Mark Payment Pending
                      </button>
                    )}
                  </div>
                )}
              </div>
            )}
          </GlassCard>
        </div>
      )}

      <NavBar />

      <style>{`
        .queue-container {
          padding: 16px 20px;
          width: 100%;
          max-width: 100%;
          margin: 0;
        }

        .page-header {
          display: flex;
          align-items: center;
          height: 60px;
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
        .queue-tabs {
          background: rgba(255,255,255,0.03);
          border: 1px solid var(--border-light);
          padding: 4px;
          border-radius: 12px;
          margin-top: 10px;
          display: flex;
          overflow-x: auto;
          scrollbar-width: none; /* Firefox */
          gap: 6px;
        }
        .queue-tabs::-webkit-scrollbar {
          display: none; /* Chrome, Safari and Opera */
        }

        .queue-tab-btn {
          flex-shrink: 0;
          padding: 10px 16px;
          border: none;
          background: transparent;
          border-radius: 8px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 12px;
          color: var(--text-muted);
          cursor: pointer;
          transition: all 0.2s ease;
          gap: 6px;
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .queue-tab-btn.active {
          background: rgba(22, 192, 122, 0.15);
          color: rgb(22, 192, 122);
        }

        .tab-count-lbl {
          font-size: 10px;
          background: rgba(255,255,255,0.1);
          padding: 2px 8px;
          border-radius: 10px;
          color: var(--text-secondary);
          font-weight: 800;
        }

        .queue-tab-btn.active .tab-count-lbl {
          background: rgb(22, 192, 122);
          color: #fff;
        }

        /* Queue Card flows */
        .queue-flow {
          display: grid;
          grid-template-columns: 1fr;
          gap: 12px;
          margin-top: 16px;
        }

        @media (min-width: 768px) {
          .queue-flow {
            grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
          }
        }

        .queue-card-wrapper {
          cursor: pointer;
          transition: transform 0.2s ease;
        }

        .queue-card-wrapper:hover {
          transform: translateY(-1.5px);
        }

        .avatar {
          width: 38px;
          height: 38px;
          border-radius: 50%;
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 15px;
          flex-shrink: 0;
        }

        .applicant-name {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 14px;
          color: var(--text-primary);
          display: block;
        }

        .applicant-email {
          font-size: 11.5px;
          color: var(--text-muted);
          display: block;
        }

        .applicant-roll {
          font-size: 10px;
          color: var(--text-muted);
          margin-top: 2px;
          display: block;
        }

        .status-pill {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 8.5px;
          padding: 2.5px 8px;
          border-radius: 20px;
          display: inline-block;
        }

        .date-lbl {
          font-size: 9.5px;
          color: var(--text-muted);
          display: block;
          margin-top: 4px;
        }

        /* Drawer popups */
        .modal-overlay {
          position: fixed;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          background: rgba(0,0,0,0.6);
          backdrop-filter: blur(5px);
          z-index: 1000;
        }

        .details-drawer {
          width: 90%;
          max-width: 440px;
          animation: slideUp 0.3s ease-out;
        }

        @keyframes slideUp {
          from { transform: translateY(50px); opacity: 0; }
          to { transform: translateY(0); opacity: 1; }
        }

        .drawer-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 18px;
          color: var(--text-primary);
        }

        .detail-rows-list {
          display: flex;
          flex-direction: column;
          gap: 10px;
          background: rgba(255,255,255,0.015);
          border: 1px solid var(--border-light);
          border-radius: 14px;
          padding: 14px;
        }

        .detail-row {
          width: 100%;
          justify-content: flex-start;
          font-size: 13px;
        }

        .detail-icon {
          color: var(--text-muted);
          margin-right: 10px;
          flex-shrink: 0;
        }

        .detail-lbl {
          color: var(--text-muted);
          margin-right: 6px;
          font-weight: 600;
        }

        .detail-val {
          color: var(--text-secondary);
          font-weight: 700;
        }

        .drawer-action-btn {
          flex: 1;
          padding: 12px;
          border-radius: 10px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
          cursor: pointer;
          border: none;
        }

        .drawer-action-btn.approve {
          background: rgb(22, 192, 122);
          color: #fff;
        }

        .drawer-action-btn.reject {
          background: rgba(239, 68, 68, 0.15);
          color: #ef4444;
          border: 1px solid rgba(239, 68, 68, 0.25);
        }

        .drawer-action-btn.payment {
          background: rgba(245, 158, 11, 0.15);
          color: #f59e0b;
          border: 1px solid rgba(245, 158, 11, 0.25);
          width: 100%;
        }

        .close-btn {
          color: var(--text-muted);
        }

        .back-btn-secondary {
          background: rgba(255,255,255,0.04);
          border: 1px solid var(--border-light);
          padding: 10px 20px;
          border-radius: 10px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
          color: var(--text-primary);
          cursor: pointer;
        }
      `}</style>
    </div>
  );
};
