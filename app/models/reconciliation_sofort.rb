require 'roo'

class ReconciliationSofort
	include AlipayDetailable
	include PayDetailable

	WARN_FILE_PATH="check_file/finance_reconciliation/sofort"
	COLUMN_NUM=35
	SKIP_LINE=1

	def valid_reconciliation(sofort_array)
		"response Analytical failure" if @array.blank?
		errmsg=""
		reconciliation_date=current_time_format("%Y%m%d",0)
		batch_id=1

		check_filename=WARN_FILE_PATH+"/paypal_finance_reconciliation_warn_"+reconciliation_date+".log"
		Rails.logger.info("check_filename:#{check_filename}")
		check_file=File.open(check_filename,"a")

		valid_all_num=sofort_array.size-SKIP_LINE
		valid_complete_num=0
		valid_succ_num=0
		valid_fail_num=0
		valid_rescue_num=0

		skip_num=0
		i=0
		sofort_array.each do |sofort_detail|
			begin
				i=i+1
				if skip_num < SKIP_LINE
					skip_num=skip_num+1
					next
				end

				rd=ReconciliationDetail.init( array_to_hash_sofort(sofort_detail,reconciliation_date,batch_id) )
				rd.valid_and_save!()
			
				valid_complete_num=valid_complete_num+1
				if(rd.reconciliation_flag==ReconciliationDetail::RECONCILIATIONDETAIL_FLAG['FAIL'])
					valid_fail_num=valid_fail_num+1
				elsif(rd.reconciliation_flag==ReconciliationDetail::RECONCILIATIONDETAIL_FLAG['SUCC'])
					valid_succ_num=valid_succ_num+1
				end
			rescue => e
				check_file << "#{rd.warn_to_file(e.message)}\n" unless rd.blank?
				Rails.logger.info(e.message)

				e.message="第#{i}行:#{e.message}"
				if valid_rescue_num==0
					errmsg=e.message
				elsif valid_rescue_num<5
					errmsg+=";"+e.message
				elsif valid_rescue_num==5
					errmsg+="..."
				end
				valid_rescue_num=valid_rescue_num+1
			end
		end
		check_file.close

		# "#{reconciliation_date} - #{reconciliation_date} <br> batch_id [ #{@batch_id} ] : </br> {all_num:#{valid_all_num} = complete_num:#{valid_complete_num} + rescue_num:#{valid_rescue_num}</br> complete_num:#{valid_complete_num} = succ_num:#{valid_succ_num} + fail_num:#{valid_fail_num} }</br>"
		outmsg="文件总比数:#{valid_all_num},导入成功比数:#{valid_complete_num},异常比数:#{valid_rescue_num} ; 
			   对账成功比数:#{valid_succ_num},对账失败比数:#{valid_fail_num}"
	end

	def valid_reconciliation_by_country(country,filename)
		skip_num=0
		if country=="de"
			skip_num=5
		elsif country=="nl"
			skip_num=2
		else
			raise "不支持的导入格式:#{country}"
		end

		errmsg=""
		xlsx=Roo::Spreadsheet.open(filename,extension: filename.to_s.split(".").last.to_sym)
		i=0
		valid_all_num=0
		valid_complete_num=0
		valid_succ_num=0
		valid_fail_num=0
		valid_rescue_num=0

		xlsx.sheet(0).each do |row|
			i =i+1
			next if i<skip_num
			begin
				valid_all_num=valid_all_num+1

				rd=ReconciliationDetail.init( DE_BOC_Bank_to_hash_sofort(row,i) ) if country=="de"
				rd=ReconciliationDetail.init( NL_ABN_Bank_to_hash_sofort(row,i) ) if country=="nl"
				rd.valid_and_save!()

				
				valid_complete_num=valid_complete_num+1
				if(rd.reconciliation_flag==ReconciliationDetail::RECONCILIATIONDETAIL_FLAG['FAIL'])
					valid_fail_num=valid_fail_num+1
				elsif(rd.reconciliation_flag==ReconciliationDetail::RECONCILIATIONDETAIL_FLAG['SUCC'])
					valid_succ_num=valid_succ_num+1
				end
			rescue => e
				Rails.logger.info("sofort对账异常:"+e.message)

				if valid_rescue_num==0
					errmsg=e.message
				elsif valid_rescue_num<5
					errmsg+=";"+e.message
				elsif valid_rescue_num==5
					errmsg+="..."
				end

				valid_rescue_num=valid_rescue_num+1
			end
		end

		outmsg="文件总比数:#{valid_all_num},导入成功比数:#{valid_complete_num},异常比数:#{valid_rescue_num} ; 
			   对账成功比数:#{valid_succ_num},对账失败比数:#{valid_fail_num}"
		
		[outmsg,errmsg]
	end

	private 
		def array_to_hash_sofort(sofort_detail,reconciliation_date,batch_id)
			raise "Row Analytical failure: size #{sofort_detail.size} !=#{COLUMN_NUM}" if sofort_detail.size!=COLUMN_NUM

			{
				'timestamp'=>sofort_detail[33],
				'name'=>sofort_detail[4],
				'transactionid'=>sofort_detail[2],
				'transaction_status'=>sofort_detail[28],
				'amt'=>sofort_detail[18].to_f,
				'currencycode'=>sofort_detail[20],
				'feeamt'=>sofort_detail[30].to_f,
				'netamt'=>sofort_detail[18].to_f - sofort_detail[30].to_f,
				'payway'=>'sofort',
				'paytype'=>'',
				'transaction_date'=>reconciliation_date,
				'batch_id'=>reconciliation_date+"_"+sprintf("%03d",batch_id),
				'reconciliation_flag'=>ReconciliationDetail::RECONCILIATIONDETAIL_FLAG['INIT']
			}
		end

		def DE_BOC_Bank_to_hash_sofort(row,i)
			sofort_detail={
				'transaction_status'=>'SUCC',
				'payway'=>'sofort',
				'feeamt'=>0.0,
				'paytype'=>'',
				'transaction_date'=>OnlinePay.current_time_format("%Y-%m-%d"),
				'batch_id'=>"upload_file_de",
				'reconciliation_flag'=>ReconciliationDetail::RECONCILIATIONDETAIL_FLAG['INIT'],
				'transactionid'=>''
			}
			j=0
			row.each do |col|
				j=j+1
				next unless j==3 || j==5 || j==6 || j==8 || j==10
				col.gsub!(/\t$/,"") if col.class.to_s=="String"
				sofort_detail["amt"],sofort_detail['netamt']=col,col if j==3
				sofort_detail["currencycode"]=col if j==5
				sofort_detail['timestamp']=col if j==6
				sofort_detail['name']=col if j==8
				sofort_detail['transactionid']=col if j==10
			end

			if sofort_detail['transactionid'].blank?
				raise "第#{i}行:对账标识(订单号)为空!"
			end
			sofort_detail
		end

		def NL_ABN_Bank_to_hash_sofort(row,i)
			sofort_detail={
				'transaction_status'=>'SUCC',
				'payway'=>'sofort',
				'paytype'=>'',
				'transaction_date'=>OnlinePay.current_time_format("%Y-%m-%d"),
				'batch_id'=>"upload_file_nl",
				'reconciliation_flag'=>ReconciliationDetail::RECONCILIATIONDETAIL_FLAG['INIT'],
				'transactionid'=>''
			}

			j=0
			row.each do |col|
				j=j+1
				next unless j==2 || j==3 || j==7 || j==8
				col.gsub!(/\t$/,"") if col.class.to_s=="String"
				sofort_detail["currencycode"]=col if j==2
				sofort_detail['timestamp']=col if j==3
				sofort_detail["amt"],sofort_detail['netamt']=col,col if j==7
				if j==8
					#sample : 
					#/TRTP/SEPA OVERBOEKING/IBAN/NL40ABNA0526989491/BIC/ABNANL2A/NAME/Z SHI/REMI/TIME140178795/EREF/NOTPROVIDED
					parttern_match=/\/REMI\/(.*?)\//.match(col)
					sofort_detail['transactionid']=parttern_match[1] unless parttern_match.blank?
				end
			end

			if sofort_detail['transactionid'].blank?
				raise "第#{i}行:对账标识(订单号)获取失败!"
			end

			sofort_detail
		end
end